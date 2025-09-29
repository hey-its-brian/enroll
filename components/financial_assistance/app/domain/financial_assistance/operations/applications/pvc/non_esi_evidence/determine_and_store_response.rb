# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/magi_medicaid/libraries/iap_library'

# Syntax:
# FinancialAssistance::Operations::Applications::Pvc::NonEsiEvidence::DetermineAndStoreResponse.new.call(fdsh_response)
# This operation is specifc for hub call

module FinancialAssistance
  module Operations
    module Applications
      module Pvc
        module NonEsiEvidence
          # This Operation determines applicants pvc medicare eligibility
          # Operation receives the Application with renewal medicare determination values
          class DetermineAndStoreResponse
            include Dry::Monads[:do, :result]
            include ::ResourceRegistryHelper

            # @param [Hash] opts The options to add pvc medicare determination to applicants
            # @option opts [Hash] :application_response_payload ::AcaEntities::MagiMedicaid::Application params
            # @return [Dry::Monads::Result]
            def call(params)
              application_entity = yield validate_and_initialize_entity(params[:payload])
              application = yield find_application(application_entity)
              _result = yield update_applicant(application_entity, application, params[:applicant_identifier])
              result = yield save_application(application, params[:applicant_identifier])
              _determination = yield update_family_determination(application)

              Success(result)
            end

            private

            def validate_and_initialize_entity(params)
              application_entity = ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(params)
              return log_and_return_failure("Failed to initialize application with hbx_id: #{params[:hbx_id]}") if application_entity.failure?

              application_entity
            end

            def find_application(application_entity)
              application = ::FinancialAssistance::Application.by_hbx_id(application_entity.hbx_id).first
              application.present? ? Success(application) : log_and_return_failure("Could not find application with given hbx_id: #{application_entity.hbx_id}")
            end

            def update_applicant(response_app_entity, application, applicant_identifier)
              response_applicant = response_app_entity.applicants.detect {|applicant| applicant.person_hbx_id == applicant_identifier}
              applicant = application.applicants.where(person_hbx_id: applicant_identifier).first

              return log_and_return_failure("applicant not found with #{applicant_identifier} for pvc Medicare") unless applicant
              return log_and_return_failure("applicant not found in response with #{applicant_identifier} for pvc Medicare") unless response_applicant

              response = update_applicant_verifications(applicant, response_applicant)
              response.nil? ? Failure('Applicant non-ESI evidence not found') : Success('Successfully updated Applicant with evidences and verifications')
            rescue StandardError => e
              log_and_return_failure("Failed to update_applicant with hbx_id #{applicant&.person_hbx_id} due to #{e.inspect}")
            end

            def update_applicant_verifications(applicant, response_applicant_entity)
              response_non_esi_evidence = response_applicant_entity.non_esi_evidence
              applicant_non_esi_evidence = applicant&.aptc_csr_eligibility&.non_esi_mec_evidence

              return unless applicant_non_esi_evidence

              if response_non_esi_evidence.aasm_state == 'outstanding'
                applicant_non_esi_evidence.determine_outstanding_state('hub_call')
              else
                applicant_non_esi_evidence.mark_as_attested
              end

              if response_non_esi_evidence.request_results.present?
                response_non_esi_evidence.request_results.each do |eligibility_result|
                  applicant_non_esi_evidence.request_results << Eligibilities::V3::RequestResult.new(eligibility_result.to_h.merge({action: 'Hub Response'}))
                end
              end

              reason = "PVC response received for #{applicant_non_esi_evidence.key.to_s.titleize} with state: #{applicant_non_esi_evidence.current_state}, updated eligibility based on four evidences"

              applicant.aptc_csr_eligibility.determine_eligibility_state(reason)

              Success(applicant)
            end

            def log_and_return_failure(message)
              pvc_logger.error(message)
              Failure(message)
            end

            def pvc_logger
              @pvc_logger ||= Logger.new("#{Rails.root}/log/pvc_non_esi_logger_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log")
            end

            def save_application(application, applicant_id)
              if application.save
                Success("Application is saved for application with hbx_id #{application.hbx_id} for applicant for identifier #{applicant_id}")
              else
                error_msg = "Failed to save  applicant id: #{applicant_id} for application: #{application.errors.full_messages.join(', ')}"
                logger.error(error_msg)
                Failure(error_msg)
              end
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
end
