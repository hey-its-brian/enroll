# frozen_string_literal: true

module FinancialAssistance
  module Operations
    module Evidences
      module Income
        # This operation automatically extends the due date for income evidences for specific families. Families are selected based on a criteria.
        class CallHub
          include Dry::Monads[:do, :result]
          include ::FinancialAssistance::Operations::Evidences::HubCallUtils
          include EventSource::Command

          private

          def build_and_validate_payload_entity(application, evidence)
            entity_monad = build_application_payload_entity(application)

            if entity_monad.failure?
              failure_reason = "Application validity: Income Evidence verification request failed due to #{entity_monad.failure}"
              result = handle_validation_failure(application, evidence, failure_reason)
              return result
            end

            validation_result = validate_applicants(entity_monad.value!, evidence, application)

            return entity_monad if validation_result.success?

            validation_result
          rescue StandardError => e
            result = handle_request_error(evidence, e)
            application.save!
            result
          end

          def validate_applicants(application_entity, evidence, application)
            validation_results = application_entity.applicants.map do |applicant_entity|
              check_eligibility_rules(applicant_entity, :income)
            end

            return Success(true) if validation_results.all?(Success)

            failed_validations = validation_results.select { |result| result.is_a?(Failure) }
            errors = failed_validations.map(&:failure).flatten.compact
            failure_reason = "Applicant validity: Income Evidence verification request failed due to #{errors}"

            handle_validation_failure(application, evidence, failure_reason)
          end

          def handle_validation_failure(application, evidence, failure_reason)
            evidence.determine_income_evidence_current_state
            handle_failed_request(evidence, application, failure_reason)
          end

          def build_event(payload)
            headers = { correlation_id: payload[:hbx_id] }
            event('events.fti.evidences.ifsv_determination_requested', attributes: payload, headers: headers.merge!({ ifsv_payload_format: "json" }))
          end
        end
      end
    end
  end
end
