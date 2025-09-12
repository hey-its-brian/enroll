# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/magi_medicaid/libraries/iap_library'

# Syntax
# ::FinancialAssistance::Operations::Applications::Pvc::NonEsiEvidence::RequestVerification.new.call({application_hbx_id: payload[:application_hbx_id]})
module FinancialAssistance
  module Operations
    module Applications
      module Pvc
        module NonEsiEvidence
        # operation to manually trigger pvc events.
        # It will take families as input and find the determined application, add evidences and publish the group of applications
          class RequestVerification
            include FinancialAssistance::Operations::Applications::Shared::NonEsiEvidenceRequest

            private

            def success_message(application_hbx_id)
              "Successfully published the pvc payload for application with hbx_id #{application_hbx_id}"
            end

            def submitted_action
              'pvc_submitted'
            end

            def submitted_message
              'PVC - Renewal verifications submitted'
            end

            def submission_failed_action
              'pvc_submission_failed'
            end

            def submission_failed_message(error)
              "PVC - Periodic verifications submission failed due to #{error}"
            end

            def eligibility_state_reason
              'PVC request for Non ESI evidence'
            end

            def process_name
              'PVC'
            end

            def build_event(cv3_application)
              event('events.fdsh.evidences.periodic_verification_confirmation', attributes: { application: cv3_application.to_h })
            end

            def logger
              pvc_logger
            end

            def publish_success_message
              "Successfully published the pvc payload"
            end

            def build_and_validate_payload(application)
              ::Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application)
            end

            def check_applicant_eligibility_rules(applicant_entity)
              ::Operations::Fdsh::PayloadEligibility::CheckApplicantEligibilityRules.new.call(applicant_entity, :non_esi_mec)
            end

            def handle_validation_failure(errors)
              log_error_and_return_failure(errors)
            end

            def pvc_logger
              @pvc_logger ||= Logger.new("#{Rails.root}/log/pvc_non_esi_logger_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
            end

            def log_error_and_return_failure(error)
              pvc_logger.error(error)
              Failure(error)
            end
          end
        end
      end
    end
  end
end