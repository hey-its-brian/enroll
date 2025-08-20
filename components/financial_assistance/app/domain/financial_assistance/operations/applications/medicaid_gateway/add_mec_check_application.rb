# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module FinancialAssistance
  module Operations
    module Applications
      module MedicaidGateway
        # This Operation adds the MEC Check to the Application(persistence object)
        # Operation receives the MEC Check results
        class AddMecCheckApplication
          include Dry::Monads[:do, :result]
          include ::ResourceRegistryHelper

          # @param [Hash] opts The options to add eligibility determination to Application(persistence object)
          # @return [Dry::Monads::Result]
          def call(params)
            payload = yield validate_params(params)
            application_entity = yield initialize_application_entity(payload)
            application = yield find_application(application_entity)
            result = yield update_applicant(application_entity, application)
            Success(result)
          end

          private

          def validate_params(params)
            return Failure('Payload is missing') unless params[:payload].present?
            if qhp_application_feature_enabled?
              return Failure('Call type is missing') unless params[:call_type].present?
              @call_type = params[:call_type]
            end

            Success(params[:payload])
          end

          def initialize_application_entity(params)
            ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(params)
          end

          def find_application(application_entity)
            application = ::FinancialAssistance::Application.by_hbx_id(application_entity.hbx_id).first
            application.present? ? Success(application) : Failure("Could not find application with given hbx_id: #{application_entity.hbx_id}")
          end

          def update_applicant(response_app_entity, application)
            enrollments = HbxEnrollment.where(:aasm_state.in => HbxEnrollment::ENROLLED_STATUSES, family_id: application.family_id)

            response_app_entity.applicants.each do |response_applicant_entity|
              applicant = find_matching_applicant(application, response_applicant_entity)
              update_applicant_verifications(applicant, response_applicant_entity, enrollments)
            end
            Success('Successfully updated Applicant with evidences and verifications')
          end

          def find_matching_applicant(application, res_applicant_entity)
            application.applicants.detect do |applicant|
              applicant.person_hbx_id == res_applicant_entity.person_hbx_id
            end
          end

          def update_applicant_verifications(applicant, response_applicant_entity, enrollments)
            response_evidence = response_applicant_entity.local_mec_evidence
            applicant_local_mec_evidence = fetch_local_mec_evidence(applicant)

            if applicant_local_mec_evidence.present?
              if qhp_application_feature_enabled?
                update_evidence(applicant, applicant_local_mec_evidence, response_evidence)
              else
                update_non_qhp_evidence(applicant, applicant_local_mec_evidence, response_evidence, enrollments)
              end
              applicant.save!
            end

            Success(applicant)
          end

          def update_evidence(applicant, applicant_local_mec_evidence, response_evidence)
            if response_evidence.aasm_state == 'outstanding'
              applicant_local_mec_evidence.determine_outstanding_state(@call_type)
            else
              applicant_local_mec_evidence.mark_as_attested
            end

            response_evidence.request_results&.each do |eligibility_result|
              applicant_local_mec_evidence.request_results << Eligibilities::V3::RequestResult.new(eligibility_result.to_h)
            end
            reason = "Hub response received for local mec evidence with state: #{applicant_local_mec_evidence.current_state}, updated eligibility based on four evidences"
            aptc_csr_eligibility = applicant.aptc_csr_eligibility
            aptc_csr_eligibility.determine_eligibility_state(reason)
            aptc_csr_eligibility.is_satisfied = aptc_csr_eligibility.evidences.all?(&:is_satisfied)
          end

          def update_non_qhp_evidence(applicant, applicant_local_mec_evidence, response_evidence, enrollments)
            if response_evidence.aasm_state == 'outstanding'
              if applicant_local_mec_evidence.enrolled_in_any_aptc_csr_enrollments?(enrollments)
                due_date = fetch_evidence_due_date_for_bulk_actions(applicant_local_mec_evidence, response_evidence)
                applicant.set_evidence_outstanding(applicant_local_mec_evidence, due_date)
              else
                applicant.set_evidence_to_negative_response(applicant_local_mec_evidence)
              end
            else
              applicant.set_evidence_attested(applicant_local_mec_evidence)
            end

            response_evidence.request_results&.each do |eligibility_result|
              applicant_local_mec_evidence.request_results << Eligibilities::RequestResult.new(eligibility_result.to_h)
            end
          end

          def fetch_local_mec_evidence(applicant)
            if qhp_application_feature_enabled?
              applicant.aptc_csr_eligibility&.local_mec_evidence
            else
              applicant.local_mec_evidence
            end
          end

          def fetch_evidence_due_date_for_bulk_actions(applicant_local_mec_evidence, response_evidence)
            return applicant_local_mec_evidence.due_on if applicant_local_mec_evidence.due_on.present?
            return unless response_evidence.request_results.any? do |result|
              FinancialAssistance::Applicant::BULK_REDETERMINATION_ACTION_TYPES.include?(result.action)
            end

            TimeKeeper.date_of_record + EnrollRegistry[:bulk_call_verification_due_in_days].item.to_i
          end
        end
      end
    end
  end
end
