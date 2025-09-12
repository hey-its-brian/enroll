# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'


module FinancialAssistance
  module Operations
    module Application
      module Evidences
        # This class is responsible for validating an application object and constructing a payload entity for FDSH service.
        #
        # @example Basic usage
        #   operation = RequestVerification.new
        #   result = operation.call(application: fa_application, payload_entity: payload)
        class RequestVerification
          include Dry::Monads[:do, :result]
          include EventSource::Command

          # Mapping of evidence types to their corresponding request types
          #
          # @return [Hash<String, Symbol>] Evidence type to request type mapping
          REQUEST_TYPE_MAPPING = {
            "esi_mec_evidence" => :esi_mec,
            "income_evidence" => :income,
            "local_mec_evidence" => :local_mec,
            "non_esi_mec_evidence" => :non_esi_mec
          }.freeze

          # Main entry point for requesting verification
          #
          # Validates the application and payload entity, builds evidence histories,
          # validates all applicants, builds and publishes an event.
          #
          # @param params [Hash] Parameters containing application and payload entity
          # @option params [FinancialAssistance::Application] :application The financial assistance application
          # @option params [Object] :payload_entity The payload entity for FDSH service
          #
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure] Success with publish result or failure message
          #
          # @example
          #   params = {
          #     application: financial_assistance_application,
          #     payload_entity: fdsh_payload_entity
          #   }
          #   result = RequestVerification.new.call(params)
          def call(params)
            application, payload_entity = yield validate(params)
            yield build_application_evidence_histories(application)
            yield validate_all_applicants(payload_entity, application)
            event_result = yield build_event(payload_entity, application)
            publish_result = yield publish_event_result(event_result)

            Success(publish_result)
          rescue StandardError => e
            Failure("FAA evidence verification error for application with hbx_id: #{params[:application].hbx_id} due to #{e.message}")
          end

          private

          # Validates the input parameters
          #
          # @param params [Hash] Input parameters
          # @option params [FinancialAssistance::Application] :application The application to validate
          # @option params [Object] :payload_entity The payload entity
          #
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure] Success with application and payload entity or failure message
          def validate(params)
            application = params[:application]
            return Failure("Application is missing") unless application.is_a?(FinancialAssistance::Application)
            return Failure("Application is invalid") unless application.valid?
            return Failure("Payload entity is missing") if params[:payload_entity].nil?

            Success([application, params[:payload_entity]])
          end

          # Builds evidence histories for all applicants in the application
          #
          # @param application [FinancialAssistance::Application] The application containing applicants
          #
          # @return [Dry::Monads::Result::Success] Always returns success
          def build_application_evidence_histories(application)
            application.applicants.each do |applicant|
              aptc_csr_eligibility = applicant.aptc_csr_eligibility
              next unless aptc_csr_eligibility
              build_evidence_histories(aptc_csr_eligibility.evidences)
            end

            Success(true)
          end

          # Builds verification histories for a collection of evidences
          #
          # @param evidences [Array] Collection of evidence objects
          #
          # @return [void]
          def build_evidence_histories(evidences)
            evidences.each do |evidence|
              evidence.build_verification_history('application_determined', 'Requested Hub for verification', 'system')
            end
          end

          # Validates all applicants against their corresponding evidence types
          #
          # @param payload_entity [Object] The payload entity containing applicants
          # @param application [FinancialAssistance::Application] The financial assistance application
          #
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure] Success with validation results or failure message
          def validate_all_applicants(payload_entity, application)
            income_evidence_errors = []
            evidence_validations = payload_entity.applicants.map do |applicant_entity|
              faa_applicant = get_fa_applicant(application, applicant_entity)
              evidences = faa_applicant.aptc_csr_eligibility.evidences

              # need to run validations against all evidence types for all applicants -- different evidence types _may_ require different validations
              evidences.map do |evidence|
                evidence_key = evidence.key
                evidence_validation = ::Operations::Fdsh::PayloadEligibility::CheckApplicantEligibilityRules.new.call(applicant_entity, REQUEST_TYPE_MAPPING[evidence_key])

                if evidence_validation.failure?
                  if evidence_key == "income_evidence"
                    income_evidence_errors << "#{applicant_entity.person_hbx_id} - #{evidence_validation.failure}"
                  else
                    handle_invalid_non_income_evidence(evidence, evidence_validation.failure)
                  end
                end

                evidence_validation
              end
            end

            handle_invalid_income_evidence(application, income_evidence_errors) unless income_evidence_errors.empty?
            application.applicants.each do |applicant|
              eligibility = applicant.aptc_csr_eligibility
              next unless eligibility

              determine_eligibility_state(eligibility)
            end

            application.save!
            return Success('All applicants evidences invalid, Hub verification did not go through enroll') if evidence_validations.flatten.all?(&:failure?)

            Success(evidence_validations)
          end

          # Finds a financial assistance applicant by person HBX ID
          #
          # @param application [FinancialAssistance::Application] The application to search
          # @param applicant_entity [Object] The applicant entity with person_hbx_id
          #
          # @return [Object] The matching financial assistance applicant
          def get_fa_applicant(application, applicant_entity)
            application.applicants.find_by { |a| a.person_hbx_id == applicant_entity.person_hbx_id }
          end

          # Handles invalid non-income evidence by marking as attested and building history
          #
          # @param evidence [Object] The evidence object to handle
          # @param failure_message [String] The failure message from validation
          #
          # @return [void]
          def handle_invalid_non_income_evidence(evidence, failure_message)
            failure_message = "#{evidence.key.to_s.titleize} Determination Request Failed due to #{failure_message}"

            evidence.mark_as_attested
            evidence.build_verification_history('hub_request_failed', failure_message, "system")
          end

          # Handles invalid income evidence for all applicants in the application
          #
          # @param financial_assistance_application [FinancialAssistance::Application] The application
          # @param invalid_app_ids [Array<String>] Array of invalid applicant IDs with error messages
          #
          # @return [void]
          def handle_invalid_income_evidence(financial_assistance_application, invalid_app_ids)
            failure_message = "Income Evidence Determination Request Failed due to invalid fields on the following applicants: #{invalid_app_ids.join(', ')}"

            financial_assistance_application.applicants.each do |applicant|
              income_evidence = applicant.aptc_csr_eligibility.income_evidence
              next unless income_evidence

              income_evidence.determine_income_evidence_current_state
              income_evidence.build_verification_history('hub_request_failed', failure_message, "system")
            end
          end

          # Determines and updates the eligibility state based on evidence status
          #
          # @param eligibility [Object] The eligibility object to update
          #
          # @return [void]
          #
          # @example
          #   determine_eligibility_state(income_evidence)
          #   # Updates eligibility state based on current evidence state
          def determine_eligibility_state(eligibility)
            reason = "hub calls made after application is determined, updated eligibility based on four evidences"
            eligibility.determine_eligibility_state(reason)
          end

          # Builds an event for the application determination
          #
          # @param payload [Object] The payload entity
          # @param application [FinancialAssistance::Application] The application
          #
          # @return [Dry::Monads::Result] The event result
          def build_event(payload, application)
            local_mec_check = application.is_local_mec_checkable?
            headers = { correlation_id: application.hbx_id }
            headers.merge!(payload_type: 'application', key: 'local_mec_check') if local_mec_check
            event('events.iap.applications.magi_medicaid_application_determined', attributes: payload.to_h, headers: headers.merge!(payload_format))
          end

          def payload_format
            {
              non_esi_payload_format: EnrollRegistry[:non_esi_h31].setting(:payload_format).item,
              esi_mec_payload_format: EnrollRegistry[:esi_mec].setting(:payload_format).item,
              ifsv_payload_format: EnrollRegistry[:ifsv].setting(:payload_format).item
            }
          end

          # Publishes the event result
          #
          # @param event_result [Object] The event result to publish
          #
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure] Success or failure message
          def publish_event_result(event_result)
            event_result.publish ? Success("Event published successfully") : Failure("Event failed to publish")
          end
        end
      end
    end
  end
end