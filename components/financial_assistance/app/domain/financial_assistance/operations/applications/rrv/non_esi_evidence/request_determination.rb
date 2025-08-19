# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module FinancialAssistance
  module Operations
    module Applications
      module Rrv
        module NonEsiEvidence
          # This operation is to publish cv3 application for rrv non_esi verification for QHP
          class RequestDetermination
            include FinancialAssistance::Operations::Applications::Shared::NonEsiEvidenceRequest

            private

            def success_message(application_hbx_id)
              "Successfully published the rrv payload for application with hbx_id #{application_hbx_id}"
            end

            def submitted_action
              'RRV_Submitted'
            end

            def submitted_message
              'RRV - Renewal verifications submitted'
            end

            def submission_failed_action
              'RRV_Submission_Failed'
            end

            def submission_failed_message(error)
              "RRV - Renewal verifications submission failed due to #{error}"
            end

            def eligibility_state_reason
              'RRV request for Non ESI evidence'
            end

            def process_name
              'RRV'
            end

            def build_event(cv3_application)
              event('events.families.iap_applications.rrvs.non_esi_evidences.determination_requested', attributes: { application: cv3_application.to_h })
            end

            def logger
              rrv_logger
            end

            def publish_success_message
              "Successfully published payload for rrv non esi"
            end

            def build_and_validate_payload(application)
              ::Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application)
            end

            def check_applicant_eligibility_rules(applicant_entity)
              ::Operations::Fdsh::PayloadEligibility::CheckApplicantEligibilityRules.new.call(applicant_entity, :non_esi_mec)
            end

            def handle_validation_failure(errors)
              Failure(errors)
            end

            def rrv_logger
              @rrv_logger ||= Logger.new("#{Rails.root}/log/rrv_non_esi_logger_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
            end
          end
        end
      end
    end
  end
end
