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
          _calls                  = yield call_hubs(application)
          _family                 = yield update_family(application)

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
            Failure("Failed to determine application due to #{application.errors.full_messages.join(', ')}")
          end
        rescue StandardError => e
          Rails.logger.error("QHP Application - Failed to determine application due to #{e.message}, #{e.backtrace.join("\n")}")
          Failure("An error occurred while determining the application: #{application.errors.full_messages.join(', ')}")
        end

        # Calls the hubs for verifying the evidences of eligibilities of applicants for the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        #
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        #
        # @note If the application is a renewal, it does not call the hubs as we are not supposed to call the hubs for system generated applications (renewals or expired_rop).
        def call_hubs(application)
          if application.is_renewal
            Success('No hub calls for renewals.')
          else
            ::Operations::Eligibilities::V3::IndividualMarket::VerificationRequests.new.call(application: application)
          end
        end

        # Updates the family associated with the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        #
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def update_family(application)
          Operations::IndividualMarket::Families::CreateOrUpdate.new.call(application: application)
        end
      end
    end
  end
end
