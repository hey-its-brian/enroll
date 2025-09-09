# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module IndividualMarketEligibility
        # Handles the migration of verification data to the new evidence-based model
        #
        # This class is responsible for generating evidence records from existing
        # verification types during the migration to the new eligibility model.
        # It handles the conversion of verification histories, state transitions,
        # and external service responses.
        #
        # @api public
        #
        # @example Basic usage
        #   handler = GenerateEvidences.new
        #   result = handler.call(applicant: applicant)
        #
        #   if result.success?
        #     puts "Evidence records generated: #{result.success}"
        #   else
        #     puts "Generation failed: #{result.failure}"
        #   end
        class GenerateEvidences
          include Dry::Monads[:do, :result]
          include EventSource::Command
          include ::ResourceRegistryHelper

          EVENT_MAPPING = {
            :outstanding => :move_to_outstanding,
            :pending => :pend,
            :rejected => :reject,
            :review => :move_to_review,
            :unverified => :unverify,
            :verified => :verify,
            :attested => :attest,
            :negative_response_received => :move_to_negative_response_received
          }.freeze

          VERIFICATION_TYPE_MAPPING = {
            'Social Security Number' => 'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence',
            'American Indian Status' => 'Eligibilities::V3::Evidences::AmericanIndianEvidence',
            'Citizenship' => 'Eligibilities::V3::Evidences::CitizenshipEvidence',
            'Immigration status' => 'Eligibilities::V3::Evidences::ImmigrationEvidence',
            'Alive Status' => 'Eligibilities::V3::Evidences::AliveEvidence'
          }.freeze

          VERIFICATION_TITLE_MAPPING = {
            'Social Security Number' => 'Social Security Number Evidence',
            'American Indian Status' => 'American Indian Evidence',
            'Citizenship' => 'Citizenship Evidence',
            'Immigration status' => 'Immigration Evidence',
            'Alive Status' => 'Alive Evidence'
          }.freeze

          VERIFICATION_KEY_MAPPING = {
            'Social Security Number' => "social_security_number_evidence",
            'American Indian Status' => "american_indian_evidence",
            'Citizenship' => "citizenship_evidence",
            'Immigration status' => "immigration_evidence",
            'Alive Status' => "alive_evidence"
          }.freeze

          DESCRIPTION_MAPPING = {
            'Social Security Number' => 'Evidence to verify the authenticity of the provided Social Security Number',
            'American Indian Status' => 'Evidence to verify federally recognized American Indian or Alaska Native tribe',
            'Citizenship' => 'Evidence to verify if the person is a US citizen',
            'Immigration status' => 'Evidence to verify lawful presence in the United States',
            'Alive Status' => 'Evidence to verify if the person is alive'
          }.freeze

          # Generates evidences for the given applicant
          #
          # @param params [Hash] Parameters for evidence generation
          # @option params [ApplicationGroup::Applicant] :applicant The applicant to generate evidences for
          # @return [Dry::Monads::Result] Success with updated applicant or Failure with error message
          # @raise [StandardError] When evidence generation fails
          def call(params)
            applicant, check_ssn_rule = yield validate(params)
            result = yield generate_evidences(applicant, check_ssn_rule)

            Success(result)
          end

          private

          def validate(params)
            if params[:applicant].nil?
              Failure(:invalid_params)
            else
              Success([params[:applicant], params[:check_ssn_rule]])
            end
          end

          def fetch_a_verification_type(v_types)
            if v_types.count > 1
              v_types.active.present? ? v_types.active.first : v_types.order_by("updated_at DESC").first
            else
              v_types.first
            end
          end

          def process_verification_type(individual_market_eligibility, person, responses)
            VerificationType::ALL_VERIFICATION_TYPES.collect do |type_name|
              v_types = person.verification_types.by_name(type_name)
              next if v_types.blank?

              verification_type = fetch_a_verification_type(v_types)
              # build new evidence
              new_evidence = build_new_evidence(individual_market_eligibility, verification_type)
              type_history_elements = verification_type.type_history_elements
              type_history_elements_with_responses = type_history_elements.where(:event_response_record_id.ne => nil).order_by("created_at ASC")
              type_history_elements_without_responses = type_history_elements.where(:event_response_record_id.eq => nil).order_by("created_at ASC")
              latest_determined_type_history_element = type_history_elements_with_responses.last
              new_evidence.determined_at = latest_determined_type_history_element.created_at if latest_determined_type_history_element.present?

              # Build verification histories
              build_and_update_verification_histories(new_evidence, type_history_elements_without_responses)

              # Build request results
              build_request_results(new_evidence, type_history_elements_with_responses, responses)

              # Build state history
              build_state_histories(new_evidence, type_history_elements)

              [new_evidence.current_state, new_evidence.is_satisfied] if new_evidence.is_active
            end.compact
          end

          def generate_evidences(applicant, check_ssn_rule)
            @migrator = ::Migrations::DataModelMigrator.new
            # Build individual_market_eligibility evidences
            individual_market_eligibility = applicant.build_individual_market_eligibility
            person_hbx_id = applicant.instance_of?(::IndividualMarket::Applicant) ? applicant.family_member.person.hbx_id : applicant.person_hbx_id
            person = Person.where(hbx_id: person_hbx_id).first

            # Person with ssn but no verification type
            # This is a data integrity issue
            # raise error and stop the process for this family
            valid_person?(person) if check_ssn_rule
            lawful_presence_determination = person.consumer_role.lawful_presence_determination
            alive_status_responses = person.consumer_role.alive_status_responses
            responses = lawful_presence_determination.ssa_responses + lawful_presence_determination.vlp_responses + alive_status_responses

            evidences_result = process_verification_type(individual_market_eligibility, person, responses)

            assign_individual_market_eligibility_attributes(individual_market_eligibility, evidences_result, applicant)

            Success(applicant)
          rescue SSNVerificationError => e
            Failure("Data integrity issue for family: #{applicant.application.family_id} - #{e.message}")
          rescue StandardError => e
            Failure("Failed to convert verification types to evidences for family: #{applicant.application.family_id} with error: #{e.message}")
          end

          def valid_person?(person)
            raise SSNVerificationError,"Person with hbx_id: #{person.hbx_id} has SSN but no SSN verification type" if person.ssn.present? && person.verification_types.unscoped.ssn_type.blank?

            true
          end

          def assign_individual_market_eligibility_attributes(individual_market_eligibility, evidences_result, applicant)
            individual_market_eligibility_current_state = determine_eligibility_state(evidences_result)
            individual_market_eligibility_is_satisfied = evidences_result.all?{ |array|  array[1] == true}

            reason = "migrating for the family #{applicant.application.family_id} to create individual_market_eligibility"
            case individual_market_eligibility_current_state
            when :satisfy
              individual_market_eligibility.satisfy(reason: reason)
            when :pend
              individual_market_eligibility.pend(reason: reason)
            end

            individual_market_eligibility.assign_attributes(is_satisfied: individual_market_eligibility_is_satisfied, determined_at: Time.now)
          end

          # Determines the eligibility state based on evidence states and application draft status.
          #
          # @param evidence_states [Array<Array>] The states and satisfaction statuses of the evidences.
          # @param is_draft [Boolean] Whether the application is in draft state.
          # @return [Symbol] The determined eligibility state.
          def determine_eligibility_state(evidence_states)
            if evidence_states.all? { |state, _| %i[verified attested].include?(state) }
              :satisfy
            else
              :pend
            end
          end

          # Creates a new evidence record from a verification type
          #
          # @api private
          # @param individual_market_eligibility [IndividualMarketEligibility] The parent eligibility record
          # @param verification_type [VerificationType] The source verification type
          # @return [Evidence] The newly created evidence record
          def build_new_evidence(individual_market_eligibility, verification_type)
            type_name = verification_type.type_name

            new_evidence = individual_market_eligibility.evidences.build(
              title: VERIFICATION_TITLE_MAPPING[type_name],
              _type: VERIFICATION_TYPE_MAPPING[type_name],
              key: VERIFICATION_KEY_MAPPING[type_name],
              description: DESCRIPTION_MAPPING[type_name]
            )

            @migrator.perform(verification_type, new_evidence)

            new_evidence.is_satisfied = [:outstanding, :rejected].include?(new_evidence.current_state) ? false : true
            new_evidence.verification_outstanding = [:outstanding, :rejected].include?(new_evidence.current_state)
            new_evidence
          end

          # Generates verification history records for an evidence
          #
          # @api private
          # @param new_evidence [Evidence] The target evidence record
          # @param type_history_elements [Array<TypeHistoryElement>] Source history elements
          # @return [void]
          def build_and_update_verification_histories(new_evidence, type_history_elements_without_responses)
            type_history_elements_without_responses.each do |type_history_element|
              verification_history = new_evidence.verification_histories.build
              @migrator.perform(type_history_element, verification_history)
            end

            latest_verification_history = new_evidence.verification_histories.order_by("date_of_action DESC").first
            return unless latest_verification_history.present?
            latest_verification_history.assign_attributes(
              is_satisfied: new_evidence.is_satisfied,
              verification_outstanding: new_evidence.verification_outstanding,
              due_on: new_evidence.due_on
            )
          end

          # Creates state transition records for an evidence
          #
          # @api private
          # @param new_evidence [Evidence] The target evidence record
          # @param type_history_elements [Array<TypeHistoryElement>] Source history elements with responses
          # @return [void]
          def build_state_histories(new_evidence, type_history_elements_with_responses)
            type_history_elements_with_responses.each do |type_history_element|
              next unless type_history_element.from_validation_status.present? && type_history_element.to_validation_status.present?
              new_model_state_history = new_evidence.state_histories.build
              new_model_state_history.to_state = type_history_element.to_validation_status
              new_model_state_history.from_state = type_history_element.from_validation_status
              new_model_state_history.event = EVENT_MAPPING[new_model_state_history.to_state]
              new_model_state_history.transition_at = type_history_element.created_at
              new_model_state_history.effective_on = type_history_element.created_at
              new_model_state_history.reason = type_history_element.update_reason
              new_model_state_history.is_eligible = ["outstanding", "rejected"].include?(new_model_state_history.to_state) ? false : true
            end
          end

          # Builds external service request results for an evidence
          #
          # @api private
          # @param new_evidence [Evidence] The target evidence record
          # @param type_history_elements [Array<TypeHistoryElement>] History elements with responses
          # @param responses [Array<EventResponse>] Raw external service responses
          # @return [void]
          def build_request_results(new_evidence, type_history_elements, responses)
            type_history_elements.each do |type_history_element|
              raw_response = responses.select{|response| response.id == BSON::ObjectId.from_string(type_history_element.event_response_record_id)}.first if responses.any?
              next if raw_response.blank?
              payload = JSON.parse(raw_response.body, symbolize_names: true)
              response_code = payload.dig(:ResponseMetadata, :ResponseCode)
              code_description = payload&.dig(:ResponseMetadata, :ResponseDescriptionText)

              new_evidence.request_results.build(
                result: nil,
                source: "FDSH",
                source_transaction_id: nil,
                updated_by: type_history_element.modifier,
                code: response_code,
                code_description: code_description,
                raw_payload: raw_response.body,
                date_of_action: raw_response.received_at,
                action: type_history_element.action
              )
            end
          end
        end

        class SSNVerificationError < StandardError; end
      end
    end
  end
end