# frozen_string_literal: true

module Operations
  module Eligibilities
    module V3
      module IndividualMarket
        # Processes SSA VLP (Social Security Administration Verification of Lawful Presence)
        # verification responses and updates applicant eligibility evidences accordingly.
        #
        # This operation handles the workflow of processing verification responses from external systems,
        # recording the response details, and updating the application's eligibility evidence status based
        # on the verification results.
        #
        # @example Processing an SSA VLP verification response
        #   result = Operations::Eligibilities::V3::IndividualMarket::SsaVlpDetermined.new.call(
        #     job_id: 'job-123',
        #     application_hbx_id: 'app-456',
        #     response: response_json_string
        #   )
        #
        #   if result.success?
        #     puts "Application updated: #{result.value!.hbx_id}"
        #   else
        #     puts "Processing failed: #{result.failure}"
        #   end
        class SsaVlpDetermined
          include Dry::Monads[:do, :result]
          include ::Operations::Transmittable::TransmittableUtils
          include ::ResourceRegistryHelper

          # Processes an SSA VLP verification response and updates the related application evidences
          #
          # @param params [Hash] Parameters for the operation
          # @option params [String] :job_id The ID of the job that initiated the verification request
          # @option params [String] :application_hbx_id The HBX ID of the application to update
          # @option params [String] :response JSON string containing the verification response data
          #
          # @return [Dry::Monads::Result::Success] On successful processing with the updated application
          # @return [Dry::Monads::Result::Failure] On processing failure with error message
          def call(params)
            validated_params = yield validate_params(params)
            transmittable_params = yield build_transmittable_params(params[:application_hbx_id])
            @job = yield find_job(validated_params[:job_id])
            @response_transmission = yield build_and_create_response_transmission(transmittable_params)
            @application = yield find_subject(validated_params[:application_hbx_id], validated_params[:app_type])
            @response_transaction = yield build_and_create_request_transaction(transmittable_params)
            @application_entity = yield validate_response(params[:response], validated_params[:app_type])
            evidences = yield update_evidences
            _determination = yield update_family_determination(@application)
            Success(evidences)
          end

          private

          # Validates the input parameters to ensure all required fields are present
          #
          # @param params [Hash] The parameters to validate
          # @return [Dry::Monads::Result::Success] If all required parameters are present
          # @return [Dry::Monads::Result::Failure] If any required parameter is missing
          def validate_params(params)
            return Failure("Missing job_id") unless params[:job_id]
            return Failure("Missing application_hbx_id") unless params[:application_hbx_id]
            return Failure("Response cannot be empty") if params[:response].empty?
            return Failure("App type is required") unless params[:app_type]
            return Failure("Determined applicants are required") unless params[:determinations]
            return Failure('type of call not specified') unless params[:call_type]
            @call_type = params[:call_type]
            @app_type = params[:app_type]

            Success(params)
          end

          # Builds the parameters needed for transmittable records
          #
          # @param hbx_id [String] The HBX ID of the application
          # @return [Dry::Monads::Result::Success] Contains the parameter hash for transmittable records
          def build_transmittable_params(hbx_id)
            values = {
              key: :ssa_vlp_verification_response,
              title: "SSA VLP verification Response",
              description: "SSA VLP verification call for application with hbx_id #{hbx_id}",
              correlation_id: hbx_id,
              transmission_id: hbx_id,
              transaction_id: hbx_id,
              started_at: DateTime.now,
              publish_on: DateTime.now,
              event: 'initial',
              state_key: :initial
            }

            Success(values)
          end

          # Creates a response transmission record to track the SSA VLP verification response
          #
          # @param values [Hash] The parameter values for the transmission
          # @return [Dry::Monads::Result::Success] With the created transmission
          # @return [Dry::Monads::Result::Failure] If transmission creation fails
          def build_and_create_response_transmission(values)
            values[:job] = @job

            create_response_transmission(values, @job)
          end

          # Finds the application based on the provided HBX ID
          #
          # @param application_hbx_id [String] The HBX ID of the application to find
          # @return [Dry::Monads::Result::Success] If application is found
          # @return [Dry::Monads::Result::Failure] If application is not found
          def find_subject(application_hbx_id, app_type)
            @application = if app_type == 'faa'
                             ::FinancialAssistance::Application.where(hbx_id: application_hbx_id).first
                           else
                             ::IndividualMarket::Application.where(hbx_id: application_hbx_id).first
                           end
            return Success(@application) if @application

            Failure("Application not found with hbx_id: #{application_hbx_id}")
          end

          # Creates a response transaction record to track the individual transmission attempt
          #
          # @param values [Hash] The parameter values for the transaction
          # @return [Dry::Monads::Result::Success] With the created transaction
          # @return [Dry::Monads::Result::Failure] If transaction creation fails
          def build_and_create_request_transaction(values)
            values[:transmission] = @response_transmission
            values[:subject] = @application

            create_response_transaction(values, @job)
          end

          # Validates and parses the response payload
          #
          # @param response [String] JSON string containing the verification response data
          # @return [Dry::Monads::Result::Success] With the parsed application entity
          # @return [Dry::Monads::Result::Failure] If validation or parsing fails
          def validate_response(response, app_type)
            payload = JSON.parse(response, symbolize_names: true)
            result = if app_type == 'faa'
                       AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(payload)
                     else
                       AcaEntities::IndividualMarket::Operations::Applications::Create.new.call(payload)
                     end

            if result.success?
              @response_transaction.json_payload = result.value!.to_h
              @response_transaction.save
              Success(result.value!)
            else
              add_errors(
                :validate_response,
                "Payload failed validation due to #{result.failure}",
                { job: @job, transmission: @response_transmission, transaction: @response_transaction }
              )
              status_result = update_status("Payload failed validation", :failed, { job: @job, transmission: @response_transmission, transaction: @response_transaction })
              return status_result if status_result.failure?
              Failure("Payload failed validation")
            end
          rescue StandardError => e
            add_errors(
              :validate_response,
              "Failed to validate response due to #{e.message}",
              { job: @job, transmission: @response_transmission, transaction: @response_transaction }
            )
            status_result = update_status("Failed to validate response", :failed, { job: @job, transmission: @response_transmission, transaction: @response_transaction })
            return status_result if status_result.failure?

            Failure("Failed to validate response")
          end

          # Updates the evidences for all applicants in the application
          #
          # @return [Dry::Monads::Result::Success] With the updated application if successful
          # @return [Dry::Monads::Result::Failure] If evidence updates fail
          # @raise [StandardError] If an unexpected error occurs during processing
          def update_evidences
            @application_entity.applicants.each do |res_applicant_entity|
              update_evidences_for_applicant(res_applicant_entity)
            end
            status_result = update_status("Evidences updated successfully", :succeeded, { job: @job, transmission: @response_transmission, transaction: @response_transaction })
            return status_result if status_result.failure?

            Success(@application)
          rescue StandardError => e
            add_errors(
              :update_evidences,
              "Failed to update evidences due to #{e.message}",
              { job: @job, transmission: @response_transmission, transaction: @response_transaction }
            )
            status_result = update_status("Failed to update evidences", :failed, { job: @job, transmission: @response_transmission, transaction: @response_transaction })
            return status_result if status_result.failure?

            Failure("Failed to update evidences")
          end

          # Updates the evidences for a specific applicant based on the response data
          #
          # @param res_applicant_entity [AcaEntities::MagiMedicaid::Applicant] The applicant entity from the response
          # @return [void]
          def update_evidences_for_applicant(res_applicant_entity)
            applicant = find_matching_applicant(res_applicant_entity)
            eligibility_entity = res_applicant_entity.eligibilities.select{ |e| e.key == :individual_market_eligibility }.first
            eligibility = applicant.individual_market_eligibility
            eligibility_entity.evidences.each do |evidence_entity|
              evidence = eligibility.evidences.detect { |e| e.key.to_sym == evidence_entity.key.to_sym }
              next unless evidence
              record_request_result(evidence, evidence_entity, applicant) if evidence_entity.request_results.present?
              record_verification_result(evidence, evidence_entity) if evidence_entity.verification_histories.present?
            end
            applicant.save
          end

          def record_request_result(evidence, evidence_entity, applicant)
            update_evidence(evidence, evidence_entity)
            result_result_entity = evidence_entity.request_results.first
            evidence.request_results.new(result_result_entity.to_h)
            assign_citizen_status(evidence_entity, applicant) if result_result_entity.source.to_s == "FDSH SSA"
            assign_five_year_bar_citizenship_result(evidence_entity, applicant) if result_result_entity.source.to_s == "FDSH VLP"
          rescue StandardError => e
            record_ingestion_result(evidence, e)
          end

          def assign_citizen_status(evidence_entity, applicant)
            json_raw_payload = evidence_entity.request_results.first.raw_payload
            response = JSON.parse(json_raw_payload, symbolize_names: true)
            response_code = response.dig(:ResponseMetadata, :ResponseCode)
            ssa_response = response.dig(:SSACompositeIndividualResponses, 0, :SSAResponse)
            return applicant.citizenship_result = ::ConsumerRole::NOT_LAWFULLY_PRESENT_STATUS unless response_code == "HS000000" && ssa_response.present?

            ssn_indicator = ssa_response[:SSNVerificationIndicator]
            citizenship_indicator = ssa_response[:PersonUSCitizenIndicator]
            applicant.citizenship_result = ::ConsumerRole::US_CITIZEN_STATUS if ssn_indicator && citizenship_indicator
            applicant.citizenship_result = ::ConsumerRole::NOT_LAWFULLY_PRESENT_STATUS if ssn_indicator && !citizenship_indicator
            applicant.citizenship_result = ::ConsumerRole::NOT_LAWFULLY_PRESENT_STATUS unless ssn_indicator
          end

          # update applicant only for vlp payloads
          def assign_five_year_bar_citizenship_result(evidence_entity, applicant)
            json_raw_payload = evidence_entity.request_results.first.raw_payload
            raw_payload = JSON.parse(json_raw_payload, symbolize_names: true)
            initial_responses = raw_payload.dig(:InitialVerificationResponseSet, :InitialVerificationIndividualResponses)
            return unless initial_responses

            individual_response = initial_responses[0]
            return unless individual_response
            individual_response_set = individual_response[:InitialVerificationIndividualResponseSet]
            return unless individual_response_set
            applicant.five_year_bar_applies = vlp_response_code_to_boolean(individual_response_set[:FiveYearBarApplyCode]) if individual_response_set.key?(:FiveYearBarApplyCode)
            applicant.five_year_bar_met = vlp_response_code_to_boolean(individual_response_set[:FiveYearBarMetCode]) if individual_response_set.key?(:FiveYearBarMetCode)
            applicant.qualified_non_citizen = qualified_non_citizen_result(raw_payload, applicant)
            applicant.citizenship_result = get_citizen_status(applicant, individual_response)
          end

          def get_citizen_status(applicant, individual_response)
            return ::ConsumerRole::NOT_LAWFULLY_PRESENT_STATUS unless ['Y', 'X'].include?(individual_response[:LawfulPresenceVerifiedCode])
            status = individual_response.dig(:InitialVerificationIndividualResponseSet, :EligStatementTxt)

            return "us_citizen" if status.eql? "UNITED STATES CITIZEN"
            return "lawful_permanent_resident" if status.eql? "LAWFUL PERMANENT RESIDENT - EMPLOYMENT AUTHORIZED"
            return "alien_lawfully_present" if ::ConsumerRole::VLP_RESPONSE_ALIEN_LEGAL_STATES.include?(status)
            return "us_citizen" if is_us_citizen?(applicant)

            "non_native_citizen"
          end

          def qualified_non_citizen_result(raw_payload, applicant)
            return unless raw_payload.dig(:ResponseMetadata, :ResponseCode) == "HS000000"
            individual_response = raw_payload.dig(:InitialVerificationResponseSet, :InitialVerificationIndividualResponses).first
            if individual_response.dig(:ResponseMetadata, :ResponseCode) == "HS000000"
              parse_qnc_code(applicant, individual_response)
            else
              individual_response.dig(:InitialVerificationIndividualResponseSet, :QualifiedNonCitizenCode)
            end
          end

          def parse_qnc_code(applicant, individual_response)
            qnc_code = individual_response.dig(:InitialVerificationIndividualResponseSet, :QualifiedNonCitizenCode)

            parse_qnc_code = case qnc_code&.upcase
                             when 'Y', 'P'
                               'Y'
                             when 'X'
                               is_us_citizen?(applicant) ? 'N' : 'Y'
                             else
                               'N'
                             end
            construct_qualified_non_citizen(applicant, parse_qnc_code)
          end

          def construct_qualified_non_citizen(applicant, parse_qnc_code)
            case parse_qnc_code
            when 'Y'
              true
            when 'N'
              false
            else
              eligible_immigration_status(applicant)
            end
          end

          def eligible_immigration_status(applicant)
            if @app_type == 'faa'
              applicant.eligible_immigration_status
            else
              applicant.demographics.eligible_immigration_status
            end
          end

          def vlp_response_code_to_boolean(code_value)
            case code_value
            when 'P', nil, 'Y' then true
            when 'X', 'N' then false
            end
          end

          def is_us_citizen?(applicant)
            if @app_type == 'faa'
              applicant.us_citizen
            else
              applicant.demographics.us_citizen
            end
          end

          def record_verification_result(evidence, evidence_entity)
            evidence.verification_histories.new(evidence_entity.verification_histories.first.to_h)
          rescue StandardError => e
            record_ingestion_result(evidence, e)
          end

          def record_ingestion_result(evidence, error)
            add_errors(
              :record_request_result,
              "Failed to record request result due to #{error.message}",
              { job: @job, transmission: @response_transmission, transaction: @response_transaction }
            )
            status_result = update_status("Failed to record request result", :failed, { job: @job, transmission: @response_transmission, transaction: @response_transaction })
            return status_result if status_result.failure?

            evidence.verification_histories.new({ action: 'hub call', update_reason: 'failed to update', updated_by: 'system' })
          end

          # Updates a specific evidence based on the verification result
          #
          # @param evidence [Eligibilities::V3::Evidence] The evidence to update
          # @param evidence_entity [AcaEntities::MagiMedicaid::Evidence] The evidence entity from the response
          # @return [void]
          def update_evidence(evidence, evidence_entity)
            if evidence_entity.current_state == :attested
              evidence.set_verified
            else
              evidence.determine_outstanding_state(@call_type)
            end
          end

          # Finds the matching applicant in the application based on the response applicant entity
          #
          # @param res_applicant_entity [AcaEntities::MagiMedicaid::Applicant] The applicant entity from the response
          # @return [FinancialAssistance::Applicant, IndividualMarket::Applicant] The matching applicant in the application
          def find_matching_applicant(res_applicant_entity)
            if @application.is_a?(::FinancialAssistance::Application)
              faa_applicant(res_applicant_entity)
            else
              uqhp_applicant(res_applicant_entity)
            end
          end

          # Finds the matching applicant in a Financial Assistance application
          #
          # @param res_applicant_entity [AcaEntities::MagiMedicaid::Applicant] The applicant entity from the response
          # @return [FinancialAssistance::Applicant] The matching applicant in the application
          def faa_applicant(res_applicant_entity)
            @application.applicants.detect do |applicant|
              applicant.person_hbx_id == res_applicant_entity.person_hbx_id
            end
          end

          # Finds the matching applicant in an Individual Market application
          #
          # @param res_applicant_entity [AcaEntities::MagiMedicaid::Applicant] The applicant entity from the response
          # @return [IndividualMarket::Applicant] The matching applicant in the application
          def uqhp_applicant(res_applicant_entity)
            @application.applicants.detect do |applicant|
              if applicant.demographics&.encrypted_ssn.present?
                encrypt_ssn(applicant.demographics.ssn) == res_applicant_entity.demographics.encrypted_ssn
              else
                applicant.person_name.family_name == res_applicant_entity.person_name&.family_name &&
                  applicant.person_name.given_name == res_applicant_entity.person_name&.given_name &&
                  applicant.demographics.dob == res_applicant_entity.demographics&.dob
              end
            end
          end

          def encrypt_ssn(ssn)
            AcaEntities::Operations::Encryption::Encrypt.new.call({ value: ssn }).value!
          end

          def update_family_determination(application)
            return Success(true) unless qhp_application_feature_enabled?

            family = application.family
            return unless family.present?

            ::Operations::Eligibilities::BuildFamilyDetermination.new.call({family: family})
          end
        end
      end
    end
  end
end