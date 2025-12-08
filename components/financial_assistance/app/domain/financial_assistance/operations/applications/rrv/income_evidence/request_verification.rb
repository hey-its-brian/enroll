# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/magi_medicaid/libraries/iap_library'

module FinancialAssistance
  module Operations
    module Applications
      module Rrv
        module IncomeEvidence
          # This Operation determines applicants rrv ifsv eligibility
          class RequestVerification
            include Dry::Monads[:do, :result]
            include EventSource::Command
            include EventSource::Logging

            def call(params)
              application_hbx_id = yield validate(params)
              application = yield fetch_application(application_hbx_id)
              yield is_application_valid?(application)
              _evidences = yield build_history_for_income_evidences(application)
              cv3_application = yield transform_and_validate_application(application)
              determination_result = yield update_family_determination(application)
              event = yield build_event(cv3_application)
              publish(event)

              Success("RRV INCOME: Successfully published payload for rrv ifsv and created history event | family_eligibility_determination: #{determination_result}")
            end

            private

            def validate(params)
              return Failure('RRV INCOME: application_hbx_id is missing') unless params[:application_hbx_id].present?

              Success(params[:application_hbx_id])
            end

            def fetch_application(application_hbx_id)
              application = ::FinancialAssistance::Application.by_hbx_id(application_hbx_id).first
              if application.present?
                Success(application)
              else
                Failure("RRV INCOME: No application found with hbx_id #{application_hbx_id}")
              end
            end

            def is_application_valid?(application)
              if application.valid?
                Success(true)
              else
                Failure("RRV INCOME: Application with hbx_id #{application.hbx_id} is invalid")
              end
            end

            def build_history_for_income_evidences(application)
              record_histories(application, 'rrv_submitted', 'RRV - Renewal verifications submitted', 'system')
              Success(true)
            end

            def transform_and_validate_application(application)
              payload_entity = ::Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application)

              if payload_entity.success?
                result = validate_applicants(payload_entity)
                if result.any?(Failure)
                  errors = result.select { |r| r.is_a?(Failure) }.map(&:failure)
                  record_application_failure(application, errors)
                  rrv_logger.error("RRV INCOME: Failed to publish: Applicants validation failed with hbx_id #{application.hbx_id} due to #{errors}")
                  update_family_determination(application)
                  return Failure(errors)
                else
                  application.save!
                end
              else
                record_application_failure(application, payload_entity.failure.messages)
                rrv_logger.error("RRV INCOME: Failed to publish: Application validation failed with hbx_id #{application.hbx_id} due to #{payload_entity.failure.messages}")
                update_family_determination(application)
              end

              payload_entity
            rescue StandardError => e
              Failure("RRV INCOME: Failed to transform application with hbx_id #{application.hbx_id} due to #{e.inspect}")
            end

            def validate_applicants(payload_entity)
              payload_entity.value!.applicants.collect do |applicant_entity|
                ::Operations::Fdsh::PayloadEligibility::CheckApplicantEligibilityRules.new.call(applicant_entity, :income)
              end.flatten.compact
            end

            def record_application_failure(application, error_messages)
              record_histories(application, 'rrv_submission_failed', "RRV - Renewal verifications submission failed due to #{error_messages}", 'system')
              assign_default_evidence_state_for_all_applicants(application)
              application.save!
            end

            def assign_default_evidence_state_for_all_applicants(application)
              application.active_applicants.each do |applicant|
                aptc_csr_eligibility = applicant.aptc_csr_eligibility
                evidence = aptc_csr_eligibility.income_evidence
                next unless evidence.present?
                evidence&.determine_income_evidence_current_state
                reason = "RRV request failed for #{evidence.key.to_s.titleize} with state: #{evidence.current_state}, updated eligibility based on four evidences"
                aptc_csr_eligibility.determine_eligibility_state(reason)
              end
            end

            def record_histories(application, action, update_reason, update_by)
              application.active_applicants.each do |applicant|
                evidence = applicant.aptc_csr_eligibility.income_evidence
                next unless evidence.present?
                evidence.build_verification_history(action, update_reason, update_by)
              end
            end

            def update_family_determination(application)
              family_id = application.family_id
              family = Family.where(id: family_id).first
              return Failure("RRV INCOME: Family not found for application hbx_id: #{application.hbx_id}")  unless family.present?

              if family.latest_application_gid == application.to_global_id&.uri&.to_s
                ::Operations::Eligibilities::BuildFamilyDetermination.new.call({family: family})
              else
                rrv_logger.error("RRV INCOME: latest application gid #{family.latest_application_gid} does not match with application gid #{application.to_global_id&.uri&.to_s} for family id: #{family.id}")
                Success("RRV INCOME: request is recorded for application with hbx_id: #{application.hbx_id}, family determination is not updated as latest application gid does not match")
              end
            end

            def rrv_logger
              @rrv_logger ||= Logger.new("#{Rails.root}/log/rrv_ifsv_logger_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
            end

            def build_event(cv3_application)
              event('events.families.iap_applications.rrvs.income_evidences.determination_requested', attributes: { application: cv3_application.to_h })
            end

            def publish(event)
              event.publish

              Success("Successfully published payload for rrv ifsv")
            end
          end
        end
      end
    end
  end
end