# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/magi_medicaid/libraries/iap_library'

module FinancialAssistance
  module Operations
    module Applications
      module Esi
        module H14
          # This Operation determines applicants esi mec eligibility
          # Operation receives the Application with esi mec determination values
          class AddEsiMecDetermination
            include Dry::Monads[:do, :result]
            include ::ResourceRegistryHelper

            # @param [Hash] opts The options to add esi mec determination to applicants
            # @option opts [Hash] :application_response_payload ::AcaEntities::MagiMedicaid::Application params
            # @return [Dry::Monads::Result]
            def call(params)
              application_entity = yield initialize_application_entity(params[:payload])
              application = yield find_application(application_entity)
              result = yield update_applicant(application_entity, application, params[:call_type])
              _determination = yield update_family_determination(application)

              Success(result)
            end

            private

            def initialize_application_entity(params)
              ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(params)
            end

            def find_application(application_entity)
              application = ::FinancialAssistance::Application.by_hbx_id(application_entity.hbx_id).first
              application.present? ? Success(application) : Failure("Could not find application with given hbx_id: #{application_entity.hbx_id}")
            end

            def update_applicant(response_app_entity, application, call_type)
              enrollments = HbxEnrollment.by_year(application.assistance_year).enrolled_and_renewing.where(family_id: application.family_id)

              response_app_entity.applicants.each do |response_applicant_entity|
                applicant = find_matching_applicant(application, response_applicant_entity)
                if qhp_application_feature_enabled?
                  update_aptc_csr_eligibility_evidence(applicant, response_applicant_entity, call_type)

                  return Failed("Failed to save application with hbx_id: #{application.hbx_id} after updating aptc_csr_eligibility evidence") unless application.save!
                else
                  update_applicant_verifications(applicant, response_applicant_entity, enrollments)
                end
              end
              Success('Successfully updated Applicant with evidences and verifications')
            end

            def update_aptc_csr_eligibility_evidence(applicant, response_applicant_entity, call_type)
              response_esi_evidence = response_applicant_entity.esi_evidence
              aptc_csr_eligibility = applicant.aptc_csr_eligibility
              return unless aptc_csr_eligibility

              esi_mec_evidence = aptc_csr_eligibility.esi_mec_evidence
              if esi_mec_evidence.blank?
                Rails.logger.error("#{esi_mec_evidence.key} Evidence Not Found for applicant with person_hbx_id: #{applicant.person_hbx_id} in application with hbx_id: #{applicant.application.hbx_id}")
                return
              end

              status = response_esi_evidence.aasm_state
              update_esi_mec_evidence(esi_mec_evidence, status, call_type)

              response_esi_evidence.request_results&.each do |request_result|
                esi_mec_evidence.request_results.build(request_result.to_h)
              end

              reason = "Hub response received for esi mec evidence with state: #{esi_mec_evidence.current_state}, updated eligibility based on four evidences"
              aptc_csr_eligibility.determine_eligibility_state(reason)
              aptc_csr_eligibility.is_satisfied = aptc_csr_eligibility.evidences.all?(&:is_satisfied)
            end

            def update_esi_mec_evidence(esi_mec_evidence, status, call_type)
              case status
              when "outstanding"
                esi_mec_evidence.determine_outstanding_state(call_type: call_type)
              else
                esi_mec_evidence.mark_as_attested
              end
            end

            def find_matching_applicant(application, res_applicant_entity)
              application.applicants.detect do |applicant|
                applicant.person_hbx_id == res_applicant_entity.person_hbx_id
              end
            end

            def update_applicant_verifications(applicant, response_applicant_entity, enrollments)
              response_esi_evidence = response_applicant_entity.esi_evidence
              applicant_esi_evidence = applicant.esi_evidence

              if applicant_esi_evidence.present?
                if response_esi_evidence.aasm_state == 'outstanding'
                  if applicant_esi_evidence.enrolled_in_any_aptc_csr_enrollments?(enrollments)
                    applicant.set_evidence_outstanding(applicant_esi_evidence)
                  else
                    applicant.set_evidence_to_negative_response(applicant_esi_evidence)
                  end
                else
                  applicant.set_evidence_attested(applicant_esi_evidence)
                end

                response_esi_evidence.request_results&.each do |eligibility_result|
                  applicant_esi_evidence.request_results << Eligibilities::RequestResult.new(eligibility_result.to_h)
                end
                applicant.save!
              end

              Success(applicant)
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
