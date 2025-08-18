# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module IndividualMarketEligibility
        # Handles the migration of evidence for financial assistance applications.
        #
        # This class validates input parameters, finds the application, and migrates evidence
        # from the old model to the new model using the `migrate_to_new_model` method.
        class CompareMigratedEvidenceValues
          include Dry::Monads[:do, :result]

          # @param params [Hash] Parameters containing the application HBX ID and additional parameters.
          # @return [Dry::Monads::Result] Success with the migrated evidence or Failure with an error message.
          def call(params)
            application = yield validate(params)
            migrated_results = yield fetch_and_validate_migrated_data(application)

            Success(migrated_results)
          end

          private

          def validate(params)
            return Failure("Invalid application provided") if params[:application].nil?

            Success(params[:application])
          end

          def fetch_and_validate_migrated_data(application)
            application_result = []
            application.applicants.each do |applicant|
              individual_market_eligibility = applicant.individual_market_eligibility
              person_hbx_id = applicant.instance_of?(::IndividualMarket::Applicant) ? applicant.family_member.person.hbx_id : applicant.person_hbx_id
              person = Person.where(hbx_id: person_hbx_id).first
              verification_types = person.verification_types
              ssn_verification_types = verification_types.by_name(VerificationType::SOCIAL_SECURITY_NUMBER)

              ssn_verification_type = fetch_a_verification_type(ssn_verification_types)
              citizenship_verification_types = verification_types.by_name(VerificationType::CITIZENSHIP)
              citizenship_verification_type = fetch_a_verification_type(citizenship_verification_types)

              alive_status_verification_types = verification_types.by_name(VerificationType::ALIVE_STATUS)
              alive_status_verification_type = fetch_a_verification_type(alive_status_verification_types)

              american_indian_status_verification_types = verification_types.by_name(VerificationType::AMERICAN_INDIAN_STATUS)
              american_indian_status_verification_type = fetch_a_verification_type(american_indian_status_verification_types)

              immigration_verification_types = verification_types.by_name(VerificationType::IMMIGRATION_STATUS)
              immigration_verification_type = fetch_a_verification_type(immigration_verification_types)

              immigration_evidence = individual_market_eligibility.immigration_evidence
              social_security_number_evidence = individual_market_eligibility.social_security_number_evidence
              citizenship_evidence = individual_market_eligibility.citizenship_evidence
              alive_evidence = individual_market_eligibility.alive_evidence
              american_indian_evidence = individual_market_eligibility.american_indian_evidence
              responses = fetch_responses(person)

              [[ssn_verification_type, social_security_number_evidence],
               [citizenship_verification_type, citizenship_evidence],
               [alive_status_verification_type, alive_evidence],
               [american_indian_status_verification_type, american_indian_evidence],
               [immigration_verification_type, immigration_evidence]].each do |old_evidence, new_evidence|
                next if old_evidence.nil? && new_evidence.nil?
                status = [application.family_id, application.hbx_id, "migrated", "", person.hbx_id]
                compare_verification_types_with_evidences(old_evidence, new_evidence, responses, status)

                application_result << status
              end
            end
            Success(application_result)
          end

          def fetch_a_verification_type(v_types)
            if v_types.count > 1
              v_types.active.present? ? v_types.active.first : v_types.order_by("updated_at DESC").first
            else
              v_types.first
            end
          end

          def fetch_responses(person)
            lpd = person.consumer_role.lawful_presence_determination
            alive_responses = person.consumer_role.alive_status_responses
            lpd.ssa_responses + lpd.vlp_responses + alive_responses
          end

          def compare_verification_types_with_evidences(old_evidence, new_evidence, responses, status)
            if old_evidence && new_evidence
              compare(old_evidence, new_evidence, responses, status)
            elsif old_evidence.present? && new_evidence.nil?
              status.push(old_evidence.key.to_s, false)
            end
          end

          def compare(old_evidence, new_evidence, responses, status)
            if evidences_matched?(old_evidence, new_evidence)
              status.push(new_evidence.key.to_s, true)
            else
              status.push(new_evidence.key.to_s, false)
            end

            if verification_histories_matched?(old_evidence, new_evidence)
              status.push("#{new_evidence.key}_verification_history", true)
            else
              status.push("#{new_evidence.key}_verification_history", false)
            end

            if request_results_matched?(old_evidence, new_evidence, responses)
              status.push("#{new_evidence.key}_request_result", true)
            else
              status.push("#{new_evidence.key}_request_result", false)
            end

            if state_transitions_matched?(old_evidence, new_evidence)
              status.push("#{new_evidence.key}_state_history", true)
            else
              status.push("#{new_evidence.key}_state_history", false)
            end

            if documents_matched?(old_evidence, new_evidence)
              status.push("#{new_evidence.key}_document", true)
            else
              status.push("#{new_evidence.key}_document", false)
            end
          end

          # old_evidence here is referring to verification type
          def evidences_matched?(old_evidence, new_evidence)
            evidence_key_matched?(old_evidence, new_evidence) &&
              evidence_other_fields_matched?(old_evidence, new_evidence) &&
              embedded_document_counts_matched?(old_evidence, new_evidence)
          end

          # old_evidence here is referring to verification type
          def evidence_other_fields_matched?(old_evidence, new_evidence)
            old_type_verification_outstanding = [:outstanding, :rejected].include?(old_evidence.validation_status.to_sym)
            old_type_is_satisfied = [:outstanding, :rejected].include?(old_evidence.validation_status.to_sym) ? false : true
            Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::GenerateEvidences::VERIFICATION_TITLE_MAPPING[old_evidence.type_name] == new_evidence.title &&
              old_evidence.due_date == new_evidence.due_on &&
              old_evidence.external_service == new_evidence.external_service &&
              Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::GenerateEvidences::DESCRIPTION_MAPPING[old_evidence.type_name] == new_evidence.description &&
              old_type_is_satisfied == new_evidence.is_satisfied &&
              old_type_verification_outstanding == new_evidence.verification_outstanding &&
              old_evidence.validation_status == new_evidence.current_state.to_s &&
              old_evidence.updated_by == new_evidence.updated_by &&
              !old_evidence.inactive == new_evidence.is_active
          end

          # old_evidence here is referring to verification type
          def evidence_key_matched?(old_evidence, new_evidence)
            Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::GenerateEvidences::VERIFICATION_KEY_MAPPING[old_evidence.type_name] == new_evidence.key
          end

          # old_evidence here is referring to verification type
          def embedded_document_counts_matched?(old_evidence, new_evidence)
            type_history_elements = old_evidence.type_history_elements
            type_history_elements_with_responses = type_history_elements.where(:event_response_record_id.ne => nil).order_by("created_at ASC")
            type_history_elements_without_responses = type_history_elements.where(:event_response_record_id.eq => nil).order_by("created_at ASC")
            type_history_elements_without_responses.count == new_evidence.verification_histories.count &&
              type_history_elements_with_responses.count == new_evidence.request_results.count
          end

          # old_evidence here is referring to verification type
          def verification_histories_matched?(old_evidence, new_evidence)
            type_history_elements = old_evidence.type_history_elements
            type_history_elements_without_response = type_history_elements.where(:event_response_record_id.eq => nil).order_by("created_at DESC").first
            old_type_verification_outstanding = [:outstanding, :rejected].include?(old_evidence.validation_status.to_sym)
            old_type_is_satisfied = [:outstanding, :rejected].include?(old_evidence.validation_status.to_sym) ? false : true
            latest_new_verification_history = new_evidence.verification_histories.order_by(:date_of_action.desc).first

            return true if type_history_elements_without_response.nil? && latest_new_verification_history.nil?

            history_matches?(old_evidence, type_history_elements_without_response,latest_new_verification_history, old_type_is_satisfied, old_type_verification_outstanding)
          end

          def history_matches?(old_evidence, type_history_elements_without_response,latest_new_verification_history, old_type_is_satisfied, old_type_verification_outstanding)
            type_history_elements_without_response.present? && latest_new_verification_history.present? &&
              type_history_elements_without_response.action == latest_new_verification_history.action &&
              type_history_elements_without_response.modifier == latest_new_verification_history.updated_by &&
              type_history_elements_without_response.update_reason == latest_new_verification_history.update_reason &&
              old_type_is_satisfied == latest_new_verification_history.is_satisfied &&
              old_type_verification_outstanding == latest_new_verification_history.verification_outstanding &&
              old_evidence.due_date == latest_new_verification_history.due_on &&
              type_history_elements_without_response.created_at == latest_new_verification_history.date_of_action
          end

          # old_evidence here is referring to verification type
          def request_results_matched?(old_evidence, new_evidence, responses)
            type_history_elements = old_evidence.type_history_elements
            type_history_elements_with_responses = type_history_elements.where(:event_response_record_id.ne => nil).order_by("created_at DESC")
            latest_new_request_result = new_evidence.request_results.order_by(:date_of_action.desc).first

            return true unless type_history_elements_with_responses.present?
            return false if type_history_elements_with_responses.present? && !latest_new_request_result.present?
            latest_type_history_element = type_history_elements_with_responses.first
            raw_response = responses.select{|response| response.id == BSON::ObjectId.from_string(latest_type_history_element.event_response_record_id)}.first if responses.any?
            payload = JSON.parse(raw_response.body, symbolize_names: true)
            response_code = payload.dig(:ResponseMetadata, :ResponseCode)
            code_description = payload&.dig(:ResponseMetadata, :ResponseDescriptionText)

            response_code == latest_new_request_result.code &&
              code_description == latest_new_request_result.code_description &&
              latest_type_history_element.action == latest_new_request_result.action
          end

          # old_evidence here is referring to verification type
          def state_transitions_matched?(old_evidence, new_evidence)
            type_history_elements = old_evidence.type_history_elements
            type_history_elements_with_responses = type_history_elements.where(:event_response_record_id.ne => nil, :to_validation_status.ne => nil).order_by("created_at DESC")
            return true unless type_history_elements_with_responses.present?
            latest_new_transition = new_evidence.state_histories.order_by(:transition_at.desc).first
            latest_type_history_element = type_history_elements_with_responses.order_by("created_at DESC").first

            if latest_type_history_element.to_validation_status == latest_new_transition.to_state &&
               latest_type_history_element.from_validation_status == latest_new_transition.from_state &&
               latest_type_history_element.created_at == latest_new_transition.transition_at &&
               latest_type_history_element.created_at == latest_new_transition.effective_on &&
               Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::GenerateEvidences::EVENT_MAPPING[latest_type_history_element.event] == latest_new_transition.event &&
               latest_type_history_element.update_reason == latest_new_transition.reason &&
               latest_new_transition.is_eligible == ["outstanding", "rejected"].include?(latest_type_history_element.to_validation_status)
              false
            else
              true
            end
          end

          def documents_matched?(old_evidence, new_evidence)
            old_evidence.vlp_documents.count == new_evidence.documents.count &&
              old_evidence.vlp_documents.all? do |old_doc|
                new_evidence.documents.any? do |new_doc|
                  old_doc.title == new_doc.title &&
                    old_doc.subject == new_doc.subject &&
                    old_doc.description == new_doc.description
                end
              end
          end
        end
      end
    end
  end
end
