# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/magi_medicaid/libraries/iap_library'

module FinancialAssistance
  module Operations
    module Applications
      module AptcCsrCreditEligibilities
        module Renewals
          # This class submit's the application send it to medicaid gateway for determination.
          # ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::SubmitDeterminationRequest.new.call({application_id: "63443986b062de03014770cd"})
          class SubmitDeterminationRequest
            include Dry::Monads[:result, :do, :try]
            include ResourceRegistryHelper

            # @param [Hash] opts The options to request eligibility determination from MedicaidGateway system
            # @option opts [BSON::ObjectId] :application_id id ofFinancialAssistance::Application
            # @return [Dry::Monads::Result]
            def call(params)
              application             = yield find_application(params)
              application             = yield validate(application)
              application             = yield submit_application(application)
              payload_param           = yield construct_payload(application)
              payload_value           = yield validate_payload(payload_param)
              _application            = yield update_application(application, payload_value)
              payload                 = yield publish_event(payload_value)

              Success(payload)
            end

            private

            # Finds the application based on the provided parameters.
            #
            # @param params [Hash] The parameters to find the application.
            # @option params [BSON::ObjectId] :application_id The ID of the application to find. OR
            # @option params [FinancialAssistance::Application] :application The application instance.
            #
            # @return [Success, Failure] Returns a Success object containing the application if found, otherwise returns a Failure object with an error message.
            def find_application(params)
              if params.key?(:application)
                if params[:application].is_a?(FinancialAssistance::Application)
                  Success(params[:application])
                else
                  Failure("Invalid value: #{params[:application]} for key application, must be a FinancialAssistance::Application")
                end
              else
                begin
                  Success(FinancialAssistance::Application.find(params[:application_id]))
                rescue Mongoid::Errors::DocumentNotFound
                  Failure("Unable to find Application with ID #{params[:application_id]}.")
                end
              end
            end

            def submit_application(application)
              application.submit
              application = retain_rop_information(application)

              return Success(application) if application.save
              Failure("Unable to save the application for given application hbx_id: #{application.hbx_id}, base_errors: #{application.errors.to_h}")
            rescue StandardError => e
              Failure("Submission failed for the application id: #{application.id} | backtrace: #{e}")
            end

            # Retains ROP information from current application to renewal application
            # This only applies when QHP Application feature is enabled.
            # This is only needed for system generated applications (including renewals).
            #
            # @param [FinancialAssistance::Application] renewal_application - renewal application instance
            #
            # @return [FinancialAssistance::Application] renewal_application - renewal application instance with ROP information retained
            def retain_rop_information(renewal_application)
              return renewal_application unless qhp_application_feature_enabled?

              current_application = renewal_application.predecessor

              renewal_application.applicants.each do |renewal_applicant|
                current_applicant = current_application.applicants.where(family_member_id: renewal_applicant.family_member_id).first

                if !current_applicant.is_applying_coverage && renewal_applicant.is_applying_coverage
                  build_history_for_applicant_now_applying_for_coverage(renewal_applicant, current_applicant)
                else
                  renewal_applicant.retain_evidence_information(current_applicant)
                end
              end

              renewal_application
            end

            def build_history_for_applicant_now_applying_for_coverage(renewal_applicant, current_applicant)
              renewal_aptc_csr_eligibility = renewal_applicant.aptc_csr_eligibility
              renewal_individual_market_eligibility = renewal_applicant.individual_market_eligibility

              renewal_aptc_csr_eligibility.evidences.each do |renewal_evidence|
                if renewal_evidence.key == 'income_evidence'
                  renewal_evidence.retain_evidence_information(current_applicant.aptc_csr_eligibility.income_evidence)
                else
                  build_history_for_newly_applying_for_coverage(renewal_evidence, current_applicant.application)
                end
              end

              renewal_individual_market_eligibility.evidences.each do |renewal_evidence|
                current_evidence = current_applicant.individual_market_eligibility.evidences.where(key: renewal_evidence.key).first

                if renewal_evidence.key == 'social_security_number_evidence'
                  if current_applicant.encrypted_ssn.present?
                    renewal_evidence.retain_evidence_information(current_evidence)
                  else
                    build_history_for_newly_applying_for_coverage(renewal_evidence, current_applicant.application)
                  end
                else
                  build_history_for_newly_applying_for_coverage(renewal_evidence, current_applicant.application)
                end
              end
            end

            def build_history_for_newly_applying_for_coverage(renewal_evidence, current_application)
              renewal_evidence.build_verification_history(
                'applicant_is_applying_for_coverage_now',
                "applicant did not apply for coverage on previous application hbx id:#{current_application.hbx_id}, no prior evidence exists to retain on renewal",
                'system'
              )
            end

            def validate(application)
              return Success(application) if application.may_submit?
              Failure("Unable to submit the application for given application hbx_id: #{application.hbx_id}, base_errors: #{application.errors.to_h}")
            end

            def construct_payload(application)
              if application.submitted?
                FinancialAssistance::Operations::Applications::Transformers::ApplicationTo::Cv3Application.new.call(application)
              else
                Failure("application is in draft state for the application id: #{application.id}")
              end
            rescue StandardError => e
              Failure(e)
            end

            def update_application(application, payload_value)
              application.assign_attributes({ eligibility_request_payload: payload_value.to_h.to_json })
              return Success(application) if application.save
              Failure("Unable to update application(hbx_id: #{application.hbx_id}) with eligibility_request_payload")
            end

            def validate_payload(payload)
              AcaEntities::MagiMedicaid::Operations::InitializeApplication.new.call(payload)
            end

            # rubocop:disable Style/MultilineBlockChain
            def publish_event(payload)
              params = {payload: payload.to_h, event_name: 'determination_requested'}

              Try do
                ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::PublishRenewalRequest.new.call(params)
              end.bind do |result|
                if result.success?
                  Success("Successfully Published for event determination_requested, with params: #{params}")
                else
                  Failure("Failed to publish for event determination_requested, with params: #{params}, failure: #{result.failure}")
                end
              end
            end
            # rubocop:enable Style/MultilineBlockChain
          end
        end
      end
    end
  end
end
