# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# rubocop:disable Style/MultilineBlockChain

module FinancialAssistance
  module Operations
    module Applications
      module AptcCsrCreditEligibilities
        module Renewals
          # This Operation creates a new renewal_draft application from a given family identifier(BSON ID),
          # ::FinancialAssistance::Operations::Applications::AptcCsrCreditEligibilities::Renewals::Renew.new.call({ family_id: "617d5cafcd9621000a5cf7e5", renewal_year: 2023 })
          class Renew
            include Dry::Monads[:result, :do, :try]
            include EventSource::Command
            include ::ResourceRegistryHelper

            attr_reader :renewal_application

            # @param [Hash] opts The options to generate renewal_draft application
            # @option opts [BSON::ObjectId] :family_id (required)
            # @option opts [Integer] :renewal_year (required)
            # @return [Dry::Monads::Result]
            def call(params)
              validated_params       = yield validate(params)
              family                 = yield find_family(validated_params[:family_id])
              _eligible              = yield check_assistance_renewal_eligibility(family)
              latest_application     = yield find_latest_application(family, validated_params)
              renewal_draft_app      = yield renew_application(latest_application, validated_params)

              Success(renewal_draft_app)
            end

            private

            def validate(params)
              return Failure('Missing family_id key') unless params.key?(:family_id)
              return Failure('Missing renewal_year key') unless params.key?(:renewal_year)
              return Failure("Cannot find family with input value: #{params[:family_id]} for key family_id") if ::Family.where(id: params[:family_id]).first.nil?
              return Failure("Invalid value: #{params[:renewal_year]} for key renewal_year, must be an Integer") if params[:renewal_year].nil? || !params[:renewal_year].is_a?(Integer)
              @renewal_job_type = params[:renewal_job_type]

              Success(params)
            end

            # Method to find a family by its ID
            #
            # @param family_id [BSON::ObjectId] The ID of the family to find
            #
            # @return [Dry::Monads::Result] Success with family object or Failure with error message
            def find_family(family_id)
              family = ::Family.only(:_id, :latest_application_gid).where(id: family_id).first
              if family
                Success(family)
              else
                Failure("Could not find family with id: #{family_id}")
              end
            end

            # Checks if the family is eligible for FAA renewal based on the latest application type OR qhp application feature flag
            #
            # @param family [Family] The family object to check
            #
            # @return [Dry::Monads::Result] Success if eligible, Failure with error message if not
            def check_assistance_renewal_eligibility(family)
              if !qhp_application_feature_enabled? || family.latest_application_type == 'faa'
                Success("Family #{family.id} is eligible for FAA renewal.")
              elsif family.latest_application.present?
                Failure("Family #{family.id} is not eligible for FAA renewal. Latest application type: #{family.latest_application_type}")
              else
                Failure("Family #{family.id} does not have a latest application")
              end
            end

            # Checks if the application is invalid based on the current year and its state
            #
            # @param application [FinancialAssistance::Application] The application to check
            # @param current_year [Integer] The current year to compare against
            #
            # @return [Boolean] True if the application is invalid, false otherwise
            def invalid_app?(application, current_year)
              application.assistance_year != current_year || application.aasm_state != 'determined'
            end

            # Finds the latest application for the family based on the validated parameters
            #
            # @param family [Family] The family object to find the application for
            # @param validated_params [Hash] The validated parameters containing family_id and renewal_year
            #
            # @return [Dry::Monads::Result] Success with the latest application or Failure with an error message
            def find_latest_application(family, validated_params)
              applications_by_family = ::FinancialAssistance::Application.where(family_id: validated_params[:family_id])

              if @renewal_job_type == 'rerun_renewal'
                latest_app = applications_by_family.by_year(validated_params[:renewal_year]).non_draft.order_by(created_at: :desc).first
                if latest_app.present?
                  if latest_app.expired?
                    Success(latest_app)
                  else
                    Failure("Renewal application already created for the year: #{validated_params[:renewal_year]} in #{latest_app.aasm_state} state.")
                  end
                else
                  Failure("Could not find any applications that are in expired state for the year: #{validated_params[:renewal_year]}.")
                end
              else
                return Failure("Renewal application already created for #{validated_params}") if applications_by_family.by_year(validated_params[:renewal_year]).present?

                current_year = validated_params[:renewal_year].pred
                application = if qhp_application_feature_enabled?
                                app = family.latest_application
                                return Failure("Family #{family.id} does not have a latest application for current year: #{current_year}") if invalid_app?(app, current_year)

                                app
                              else
                                applications_by_family.newest_determined_by_year(current_year).first
                              end

                if application&.eligible_for_renewal?
                  Success(application)
                else
                  Failure("Could not find any applications that are renewal eligible: #{validated_params}.")
                end
              end
            rescue SystemStackError => e
              Failure("Critical Error: Unable to find application from database for family id: #{validated_params[:family_id]}.\n error_message: #{e.message} \n backtrace: #{e.backtrace.join("\n")}")
            end

            def renew_application(application, validated_params)
              application = create_renewal_draft_application(application, validated_params)

              return Failure("Unable to create renewal application - #{application.failure} with params: (#{validated_params})") if application.failure?

              application
            end

            # Prepares parameters for copying an application
            # @param application_id [BSON::ObjectId] The ID of the application to be copied
            # @return [Hash] Parameters used by the Copy operation
            def copy_params(application_id)
              if qhp_application_feature_enabled?
                {
                  application_id: application_id,
                  origin: :system,
                  generation_reason: :renewal,
                  renewal: true
                }
              else
                { application_id: application_id, renewal: true }
              end
            end

            # I agree + 5 years
            ### Copy application via UI: I agree, 5 years to renew
            ### Copy application via renewal - I agree, -1 years to renew
            # I disagree + x years
            ### Copy application via UI: I disagree + x years
            ### Copy application via renewal - I disagree + (x years - 1)
            # I agree + <5 years
            ### Copy application via UI: I agree, 5 years to renew
            ### Copy application via renewal - I agree + (x years -1)

            # If years to renew is 0, set to income_verification_extension_required
            def create_renewal_draft_application(application, validated_params)
              Try() do
                ::FinancialAssistance::Operations::Applications::Copy.new
              end.bind do |renewal_application_factory|
                copied_result = renewal_application_factory.call(copy_params(application.id))
                return Failure(copied_result.failure[:detailed_error_message]) if copied_result.failure?

                @renewal_application = copied_result.success
                calculated_renewal_base_year = calculate_renewal_base_year(application)
                additional_attrs = {
                  aasm_state: 'renewal_draft',
                  assistance_year: validated_params[:renewal_year],
                  years_to_renew: calculate_years_to_renew(application),
                  renewal_base_year: calculated_renewal_base_year,
                  predecessor_id: application.id,
                  effective_date: Date.new(validated_params[:renewal_year])
                }
                renewal_application.assign_attributes(additional_attrs)
                renewal_application.full_medicaid_determination = application.full_medicaid_determination if full_medicaid_determination_feature_enabled?
                update_aasm_state(application, renewal_application, renewal_application_factory)
                renewal_application.renewal_draft_blocker_reasons = [@failure_reason] if @failure_reason

                if qhp_application_feature_enabled?
                  renewal_application.build_ivl_eligibility_with_evidences
                  renewal_application.build_aptc_eligibilities_evidences
                end

                renewal_application.save
                if renewal_application.renewal_draft?
                  Success(renewal_application)
                else
                  Failure(
                    "Renewal Application with hbx_id: #{
                      renewal_application.hbx_id} is in #{
                        renewal_application.aasm_state} state instead of renewal_draft because: #{
                          @failure_reason || 'Unknown'}. Might require user input."
                  )
                end
              end.to_result
            end

            def full_medicaid_determination_feature_enabled?
              feature = FinancialAssistanceRegistry[:full_medicaid_determination_step]
              feature.enabled? && feature.settings(:annual_eligibility_redetermination).item
            end

            # Updates the AASM state of the renewal application based on the current application state.
            # Calls the appropriate event to transition the state so that the transition is recorded.
            #
            # @param application [FinancialAssistance::Application] The original application
            def update_aasm_state(application, renewal_application, renewal_application_factory)
              new_state = find_aasm_state(application, renewal_application_factory)

              case new_state
              when 'income_verification_extension_required'
                renewal_application.set_income_verification_extension_required
              when 'applicants_update_required'
                renewal_application.set_applicants_update_required
              end
            end

            def find_aasm_state(application, renewal_application_factory)
              if !@renewal_job_type && (application.years_to_renew == 0 || application.years_to_renew.nil?)
                @failure_reason = 'years_to_renew is 0 or nil'
                return 'income_verification_extension_required'
              end

              @failure_reason = if renewal_application_factory.family_members_changed
                                  'family_members_changed'
                                elsif missing_relationships?(renewal_application_factory.relationships_changed)
                                  'missing_relationships'
                                elsif !renewal_application.valid_relationship_kinds?
                                  'invalid_relationships'
                                elsif renewal_application_factory.claiming_applicants_missing
                                  'claiming_applicants_missing'
                                end

              return 'applicants_update_required' if @failure_reason

              'renewal_draft'
            end

            def missing_relationships?(relationships_changed)
              relationships_changed && !renewal_application.relationships_complete?
            end

            def calculate_years_to_renew(application)
              return application.years_to_renew if @renewal_job_type == 'rerun_renewal'

              if application.years_to_renew.present? && application.years_to_renew > 0
                application.years_to_renew.to_i - 1
              else
                application.years_to_renew || 0
              end
            end

            def calculate_renewal_base_year(application)
              return application.renewal_base_year if @renewal_job_type == 'rerun_renewal'
              return application.renewal_base_year if application.renewal_base_year.present?

              application.calculate_renewal_base_year
            end
          end
        end
      end
    end
  end
end
# rubocop:enable Style/MultilineBlockChain
