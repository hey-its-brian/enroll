# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/magi_medicaid/libraries/iap_library'

module FinancialAssistance
  module Operations
    module Applications
      module Rrv
        module NonEsiEvidence
          # This Operation processes the response determination for Non ESI Evidence requests
          class DetermineAndStoreResponse
            include Dry::Monads[:do, :result]

            def call(params)
              validated_params = yield validate_params(params)
              application_entity = yield initialize_application_entity(validated_params[:payload])
              application = yield find_application(application_entity)
              _applicant_result = yield update_applicant(application_entity, application, validated_params[:applicant_identifier])
              result = yield save_application(application, validated_params[:applicant_identifier])
              _determination = yield update_family_determination(application)

              Success(result)
            end

            private

            def validate_params(params)
              return Failure('payload is missing') unless params[:payload]
              return Failure("Determined applicants are required") unless params[:applicant_identifier]

              Success(params)
            end

            def initialize_application_entity(params)
              ::AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(params)
            end

            def find_application(application_entity)
              application = ::FinancialAssistance::Application.by_hbx_id(application_entity.hbx_id).first
              application.present? ? Success(application) : Failure("Could not find application with given hbx_id: #{application_entity.hbx_id}")
            end

            def update_applicant(response_app_entity, application, applicant_identifier)
              response_applicant = response_app_entity.applicants.detect {|applicant| applicant.person_hbx_id == applicant_identifier}
              applicant = application.applicants.where(person_hbx_id: applicant_identifier).first

              return Failure("applicant not found with #{applicant_identifier} for rrv") unless applicant
              return Failure("applicant not found in response with #{applicant_identifier} for rrv") unless response_applicant
              response = update_applicant_verifications(applicant, response_applicant)
              response.nil? ? Failure('Applicant non-ESI evidence not found') : Success('Successfully updated Applicant with evidences and verifications')
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
                  applicant_non_esi_evidence.request_results << Eligibilities::V3::RequestResult.new(eligibility_result.to_h.merge(action: "Hub Response"))
                end
              end

              Success(applicant)
            end

            def save_application(application, applicant_id)
              if application.save
                Success("Application is saved for application with hbx_id #{application.hbx_id} for applicant for identifier #{applicant_id}")
              else
                Failure("Failed to save application: #{application.errors.full_messages.join(', ')}")
              end
            end

            def update_family_determination(application)
              family = application.family
              return Failure("RRV NON ESI: Family not found for application hbx_id: #{application.hbx_id}") unless family.present?

              if family.latest_application_gid == application.to_global_id&.uri&.to_s
                ::Operations::Eligibilities::BuildFamilyDetermination.new.call({family: family})
              else
                Success("Non ESI response is loaded for application with hbx_id: #{application.hbx_id}, family determination is not updated as latest application gid does not match")
              end
            end
          end
        end
      end
    end
  end
end
