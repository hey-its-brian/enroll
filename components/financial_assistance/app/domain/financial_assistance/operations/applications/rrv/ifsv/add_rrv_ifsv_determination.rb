# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/magi_medicaid/libraries/iap_library'

module FinancialAssistance
  module Operations
    module Applications
      module Rrv
        module Ifsv
          # This Operation determines applicants rrv ifsv eligibility
          # Operation receives the Application with renewal ifsv determination values
          class AddRrvIfsvDetermination
            include Dry::Monads[:do, :result]
            include ::ResourceRegistryHelper

            # @param [Hash] opts The options to add rrv ifsv determination to applicants
            # @option opts [Hash] :application_response_payload ::AcaEntities::MagiMedicaid::Application params
            # @return [Dry::Monads::Result]
            def call(params)
              application_entity = yield initialize_application_entity(params[:payload])
              application = yield find_application(application_entity)
              result = yield update_applicant(application_entity, application)
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

            def find_matching_applicant(application, res_applicant_entity)
              application.applicants.detect do |applicant|
                applicant.person_hbx_id == res_applicant_entity.person_hbx_id
              end
            end

            def update_applicant(response_app_entity, application)
              enrollments = HbxEnrollment.by_year(application.assistance_year).enrolled_and_renewing.where(family_id: application.family_id)
              is_ifsv_eligible = response_app_entity.tax_households.first.is_ifsv_eligible
              status = is_ifsv_eligible ? "verified" : "outstanding"

              response_app_entity.applicants.each do |response_applicant_entity|
                applicant = find_matching_applicant(application, response_applicant_entity)
                if applicant.income_evidence.blank?
                  Rails.logger.error("Income Evidence not found for applicant with person_hbx_id: #{applicant.person_hbx_id} in application with hbx_id: #{application.hbx_id}")
                  next
                end
                update_applicant_evidence(applicant, status, response_applicant_entity, enrollments)
              end
              Success('Successfully updated Applicant with evidence')
            end

            def update_applicant_evidence(applicant, status, response_applicant_entity, enrollments)
              response_income_evidence = response_applicant_entity.income_evidence
              income_evidence = applicant.income_evidence
              # below is a quick fix to avoid duplicate request results, rrv process needs refactoring
              return if income_evidence.request_results.detect{|evidence| evidence.action == "RRV Response" && evidence.created_at.to_date >= Date.today - 1}.present?

              case status
              when "verified"
                applicant.set_income_evidence_verified
              when "outstanding"
                if !EnrollRegistry.feature_enabled?(:ifsv_income_nrr) || income_evidence.enrolled_in_any_aptc_csr_enrollments?(enrollments)
                  applicant.set_evidence_outstanding(income_evidence)
                else
                  applicant.set_evidence_to_negative_response(income_evidence)
                end
              end

              response_income_evidence.request_results&.each do |request_result|
                income_evidence.request_results << Eligibilities::RequestResult.new(request_result.to_h.merge(action: "RRV Response"))
              end
              applicant.save!
            end

            def update_family_determination(application)
              return Success(true) unless qhp_application_feature_enabled?

              family = application.family
              return unless family.present?

              ::Operations::Eligibilities::BuildFamilyDetermination.new.call({family: family}) if family.latest_application_gid == application.to_global_id&.uri&.to_s
            end
          end
        end
      end
    end
  end
end
