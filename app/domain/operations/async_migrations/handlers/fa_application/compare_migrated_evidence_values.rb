# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module FAApplication
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
              old_income_evidence = applicant.income_evidence
              old_esi_evidence = applicant.esi_evidence
              old_local_mec_evidence = applicant.local_mec_evidence
              old_non_esi_evidence = applicant.non_esi_evidence

              new_income_evidence = applicant.aptc_csr_eligibility.income_evidence
              new_esi_evidence = applicant.aptc_csr_eligibility.esi_mec_evidence
              new_local_mec_evidence = applicant.aptc_csr_eligibility.local_mec_evidence
              new_non_esi_evidence = applicant.aptc_csr_eligibility.non_esi_mec_evidence

              [[old_income_evidence, new_income_evidence], [old_esi_evidence, new_esi_evidence], [old_local_mec_evidence, new_local_mec_evidence], [old_non_esi_evidence, new_non_esi_evidence]].each do |old_evidence, new_evidence|
                status = [application.hbx_id, "migrated", "", applicant.person_hbx_id]
                next unless old_evidence && new_evidence
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

                if request_results_matched?(old_evidence, new_evidence)
                  status.push("#{new_evidence.key}_request_result", true)
                else
                  status.push("#{new_evidence.key}_request_result", false)
                end

                if state_transitions_matched?(old_evidence, new_evidence)
                  status.push("#{new_evidence.key}_state_history", true)
                else
                  status.push("#{new_evidence.key}_state_history", false)
                end
                application_result << status
              end
            end
            Success(application_result)
          end

          def evidences_matched?(old_evidence, new_evidence)
            evidence_key_matched?(old_evidence, new_evidence) &&
              evidence_other_fields_matched?(old_evidence, new_evidence) &&
              embedded_document_counts_matched?(old_evidence, new_evidence)
          end

          def evidence_other_fields_matched?(old_evidence, new_evidence)
            old_evidence.title == new_evidence.title &&
              old_evidence.due_on == new_evidence.due_on &&
              old_evidence.external_service == new_evidence.external_service &&
              old_evidence.description == new_evidence.description &&
              old_evidence.is_satisfied == new_evidence.is_satisfied &&
              old_evidence.verification_outstanding == new_evidence.verification_outstanding &&
              old_evidence.aasm_state == new_evidence.current_state.to_s &&
              old_evidence.updated_by == new_evidence.updated_by &&
              new_evidence.is_active == true
          end

          def evidence_key_matched?(old_evidence, new_evidence)
            Operations::AsyncMigrations::Handlers::FAApplication::MigrateEvidence::EVIDENCE_KEY_MAPPING[old_evidence.key].to_s == new_evidence.key
          end

          def embedded_document_counts_matched?(old_evidence, new_evidence)
            old_evidence.verification_histories.count == new_evidence.verification_histories.count &&
              old_evidence.request_results.count == new_evidence.request_results.count &&
              old_evidence.workflow_state_transitions.count == new_evidence.state_histories.count
          end

          def verification_histories_matched?(old_evidence, new_evidence)
            latest_old_verification_history = old_evidence.verification_histories.order_by(:date_of_action.desc).first
            latest_new_verification_history = new_evidence.verification_histories.order_by(:date_of_action.desc).first

            return true if latest_old_verification_history.nil? && latest_new_verification_history.nil?

            latest_old_verification_history.action == latest_new_verification_history.action &&
              latest_old_verification_history.updated_by == latest_new_verification_history.updated_by &&
              latest_old_verification_history.update_reason == latest_new_verification_history.update_reason &&
              latest_old_verification_history.is_satisfied == latest_new_verification_history.is_satisfied &&
              latest_old_verification_history.verification_outstanding == latest_new_verification_history.verification_outstanding &&
              latest_old_verification_history.due_on == latest_new_verification_history.due_on &&
              latest_old_verification_history.date_of_action == latest_new_verification_history.date_of_action
          end

          def request_results_matched?(old_evidence, new_evidence)
            latest_old_request_result = old_evidence.request_results.order_by(:date_of_action.desc).first
            latest_new_request_result = new_evidence.request_results.order_by(:date_of_action.desc).first

            return true if latest_old_request_result.nil? && latest_new_request_result.nil?

            latest_old_request_result.result == latest_new_request_result.result &&
              latest_old_request_result.source == latest_new_request_result.source &&
              latest_old_request_result.source_transaction_id == latest_new_request_result.source_transaction_id &&
              latest_old_request_result.code == latest_new_request_result.code &&
              latest_old_request_result.code_description == latest_new_request_result.code_description &&
              latest_old_request_result.action == latest_new_request_result.action &&
              (latest_old_request_result.raw_payload.present? == latest_new_request_result.raw_payload.present?)
          end

          def state_transitions_matched?(old_evidence, new_evidence)
            latest_old_transition = old_evidence.workflow_state_transitions.order_by(:date_of_action.desc).first
            latest_new_transition = new_evidence.state_histories.order_by(:transition_at.desc).first

            return true if latest_old_transition.nil? && latest_new_transition.nil?

            latest_old_transition.to_state == latest_new_transition.to_state &&
              latest_old_transition.from_state == latest_new_transition.from_state &&
              latest_old_transition.transition_at == latest_new_transition.transition_at &&
              latest_old_transition.event == latest_new_transition.event &&
              latest_old_transition.comment == latest_new_transition.comment &&
              latest_old_transition.reason == latest_new_transition.reason &&
              (latest_new_transition.is_eligible.nil? || !latest_new_transition.effective_on.present?)
          end
        end
      end
    end
  end
end
