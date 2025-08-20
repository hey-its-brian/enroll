# frozen_string_literal: true

module FinancialAssistance
  module Operations
    module Evidences
      module LocalMec
        # This operation automatically extends the due date for non-ESI evidences for specific families. Families are selected based on a criteria.
        class CallHub
          include Dry::Monads[:do, :result]
          include ::FinancialAssistance::Operations::Evidences::HubCallUtils
          include EventSource::Command

          private

          def build_and_validate_payload_entity(application, evidence)
            entity_monad = build_application_payload_entity(application)

            if entity_monad.failure?
              failure_reason = "Application validity: Local Mec Evidence verification request failed due to #{entity_monad.failure}"
              result = handle_validation_failure(application, evidence, failure_reason)
              return result
            end

            applicant_result = validate_applicant(entity_monad.value!, evidence, application)

            return entity_monad if applicant_result.success?

            applicant_result
          rescue StandardError => e
            result = handle_request_error(evidence, e)
            application.save!
            result
          end

          def validate_applicant(application_entity, evidence, application)
            applicant = evidence.eligibility.eligible

            applicant_entity = application_entity.applicants.select { |appl| appl.person_hbx_id == applicant.person_hbx_id }.first
            validation_result = check_eligibility_rules(applicant_entity, :local_mec)


            return Success(true) if validation_result.success?
            errors = validation_result.failure
            failure_reason = "Applicant validity: Local Mec Evidence verification request failed due to #{errors}"

            handle_validation_failure(application, evidence, failure_reason)
          end

          def handle_validation_failure(application, evidence, failure_reason)
            evidence.mark_as_attested
            handle_failed_request(evidence, application, failure_reason)
          end

          def build_event(payload)
            headers = { payload_type: 'application', key: 'local_mec_check', call_type: 'hub_call' }
            event('events.iap.mec_check.mec_check_requested', attributes: payload, headers: headers.merge!({ local_mec_payload_format: "json" }))
          end
        end
      end
    end
  end
end
