# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Application
      # operation to submit an individual market application, determine applicants, generate evidences, and determine the application
      class SubmitAndDetermine
        include Dry::Monads[:do, :result, :try]

        # submits the application
        # determines each applicant
        # generates evidences for each applicant
        # sets the current state to determined, which triggers the on_determination callbacks
        # this will trigger the creation of a new tax household and update or create a family determination etc
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @return [Dry::Monads::Result] Success with message
        def call(application:)
          application             = yield validate(application)
          application             = yield submit_application(application)
          applicant_results       = yield determine_applicants(application)
          _applicants             = yield build_evidences(applicant_results)
          determined_application  = yield determine_application(application)
          _application_entity     = yield build_app_entity(application)
          _calls                  = yield call_hubs(application)
          _family                 = yield update_family(application)
          _enrollments            = yield generate_enrollments(application)
          _notification           = yield trigger_notifications(application)
          Success(determined_application)
        end

        private

        # validates the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @return [Dry::Monads::Result] Success with message
        def validate(application)
          return Failure('Invalid application type. Expected IndividualMarket::Application.') unless application.is_a?(::IndividualMarket::Application)
          return Failure('Invalid application is not initial.') unless application.current_state == :initial
          return Failure("Invalid Family for given application with hbx_id: #{application.hbx_id}") unless application.family.is_a?(::Family)
          return Failure("Invalid application due to #{application.errors.full_messages.join(', ')}") unless application.valid?
          Success(application)
        end

        # submits the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        #
        # @return [Dry::Monads::Result] Success with message
        def submit_application(application)
          application.submit
          application.set_submit
          if application.save!
            Success(application)
          else
            application.failed_submission
            Failure("Failed to submit application due to #{application.errors.full_messages.join(', ')}")
          end
        rescue StandardError => e
          Rails.logger.error("QHP Application - Failed to submit application due to #{e.message}, #{e.backtrace.join("\n")}")
          Failure("An error occurred while submitting the application: #{application.errors.full_messages.join(', ')}")
        end

        # determines each applicant
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @return [Dry::Monads::Result] Success with message
        def determine_applicants(application)
          applicants_results = application.applicants.map do |applicant|
            Operations::IndividualMarket::Applicant::Determine.new.call({application: application, applicant: applicant})
          end
          failed_applicants = applicants_results.select(&:failure?)
          if failed_applicants.any?
            Rails.logger.error("QHP Application - Failed to determine applicants: #{failed_applicants.map(&:failure).join(', ')}")
            Failure("Failed to determine applicants: #{failed_applicants.map(&:failure).join(', ')}")
          else
            Success(applicants_results.map(&:success))
          end
        end

        # generates evidences for each applicant
        #
        # @param applicant_results [Array] array of applicant results
        # @return [Dry::Monads::Result] Success with message
        def build_evidences(applicant_results)
          applicants = applicant_results.map do |applicant|
            Try do
              applicant.build_individual_market_evidences
            rescue StandardError => e
              Failure("Failed to generate evidences for applicant #{applicant.id}: #{e.message}")
            end
          end
          Success(applicants)
        end

        # sets the current state to determined, which triggers the on_determination callbacks
        # this will trigger the creation of a new tax household and update or create a family determination
        # it will also trigger the hub calls
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @return [Dry::Monads::Result] Success with message
        def determine_application(application)
          application.determine
          if application.save!
            Success(application)
          else
            application.failed_determination
            Failure("Failed to determine application due to #{application.errors.full_messages.join(', ')}")
          end
        rescue StandardError => e
          Rails.logger.error("QHP Application - Failed to determine application due to #{e.message}, #{e.backtrace.join("\n")}")
          Failure("An error occurred while determining the application: #{application.errors.full_messages.join(', ')}")
        end

        # Builds the application entity required for verification services
        #
        # Uses the Fdsh BuildAndValidateApplicationPayload operation to create the
        # standardized application entity representation needed by verification services.
        #
        # @param application [FinancialAssistance::Application] The application to build an entity from
        # @return [Dry::Monads::Result::Success] Always returns success as the actual entity is stored in @application_entity
        def build_app_entity(application)
          @application_entity = Operations::IndividualMarket::Application::TransformToEntity.new.call(application)
          return Failure("Failed to build application entity for #{application.id}, #{@application_entity.failure}") if @application_entity.failure?

          Success(nil)
        end

        # Calls the hubs for verifying the evidences of eligibilities of applicants for the application
        #
        # @param application entity [IndividualMarket::Application] the individual market application
        #
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        #
        # @note If the application is a renewal, it does not call the hubs as we are not supposed to call the hubs for system generated applications (renewals or expired_rop).
        def call_hubs(application)
          if application.is_renewal
            Success('No hub calls for renewals.')
          else
            params = { application: application, application_entity: @application_entity }
            ::Operations::Eligibilities::V3::IndividualMarket::VerificationRequests.new.call(params)
          end
        end

        # Updates the family associated with the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        #
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def update_family(application)
          result = Operations::IndividualMarket::Families::CreateOrUpdate.new.call(application: application)
          return result if result.success?
          application.failed_family_sync
          result
        rescue StandardError => e
          Rails.logger.error("QHP Application - Failed to update family due to #{e.message}, #{e.backtrace.join("\n")}")
          Failure("An error occurred while updating the family: #{e.message}")
        end

        def generate_enrollments(application)
          return Success("apply aggregate to enrollment is disabled") unless EnrollRegistry.feature_enabled?(:apply_aggregate_to_enrollment)
          return Success("No enrollments to generate") unless has_enrollments_to_generate?(application)

          result = Operations::Individual::OnNewDetermination.new.call({family: application.family, year: application.assistance_year})
          return result if result.success?

          Failure("Failed to generate enrollments: #{result.failure}")
        rescue StandardError => e
          Rails.logger.error("QHP Application - Failed to generate enrollments due to #{e.message}, #{e.backtrace.join("\n")}")
          Failure("An error occurred while generating enrollments: #{e.message}")
        end

        def has_enrollments_to_generate?(application)
          application.family.active_household&.hbx_enrollments&.enrolled_and_renewal&.individual_market&.by_health&.by_year(application.assistance_year)&.any?
        end

        # Triggers qhp eligibility notifications the for all applicants in the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @param application_entity [AcaEntities::IndividualMarket::Application] the individual market application entity
        #
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def trigger_notifications(application)
          if application.is_renewal
            Success('No notifications for renewals.')
          else
            params = { application: application, application_entity: @application_entity }
            Operations::IndividualMarket::Application::TriggerQhpEligibilityNotices.new.call(params)
          end
        end
      end
    end
  end
end
