# frozen_string_literal: true

module Operations
  module IndividualMarket
    module Applications
      module Renewals
        # Operation to submit and determine an individual market application for a given application ID.
        class SubmitAndDetermine
          include Dry::Monads[:result, :do]
          include EventSource::Command

          # Finds the application by ID
          # Finds the family associated with the application
          # Finds the latest determined application for the family (application is expected to be the current year's)
          # Calls ::Operations::IndividualMarket::Application::SubmitAndDetermine
          # Retains evidence information from the current application to the renewal application
          def call(application_id:)
            application           = yield find_application(application_id)
            family                = yield find_family(application)
            current_application   = yield fetch_current_application(family)
            application           = yield submit_and_determine(application)
            application           = yield retain_evidence_info(current_application, application)
            application           = yield persist(application)
            _family_determination = yield regenerate_family_determination(application)

            Success(application)
          end

          private

          # Finds the application by ID
          #
          # @param application_id [String] The ID of the application to find
          #
          # @return [Dry::Monads::Result] Success with the application or Failure with an error message
          def find_application(application_id)
            application = ::IndividualMarket::Application.where(id: application_id).first

            if application
              if application.initial?
                Success(application)
              else
                Failure("Application with ID #{application_id} is not in initial state.")
              end
            else
              Failure("Application with ID #{application_id} not found.")
            end
          end

          # Finds the family associated with the application
          #
          # @param application [IndividualMarket::Application] The application to find the family for
          #
          # @return [Dry::Monads::Result] Success with the family or Failure with an error message
          def find_family(application)
            family = application.family

            if family
              Success(family)
            else
              Failure("Family for application with ID #{application.id} not found.")
            end
          end

          # Fetches the latest determined application for the family
          #
          # @param family [Family] The family to find the latest determined application for
          #
          # @return [Dry::Monads::Result] Success with the latest determined application or Failure with an error message
          #                               The latest application can be IndividualMarket::Application or FinancialAssistance::Application
          #
          # @note This method resets the latest application instance variable to ensure it is not
          #       cached as we will set with a renewal application in one of the next steps.
          def fetch_current_application(family)
            latest_app = family.latest_application
            family.reset_latest_application

            if latest_app
              Success(latest_app)
            else
              Failure("No current application found for family with ID #{family.id}.")
            end
          end

          # Submits and determines the application
          #
          # @param application [IndividualMarket::Application] The application to submit and determine
          #
          # @return [Dry::Monads::Result] Success with the application or Failure with an error message
          def submit_and_determine(application)
            ::Operations::IndividualMarket::Application::SubmitAndDetermine.new.call(application: application)
          end

          # Retains evidence information from the current application to the renewal application
          #
          # @param current_application [IndividualMarket::Application] The current application to retain evidence from
          # @param application [IndividualMarket::Application] The renewal application to retain evidence to
          #
          # @return [Dry::Monads::Result] Success with the renewal application or Failure with an error message
          def retain_evidence_info(current_application, application)
            application.applicants.each do |applicant|
              current_applicant = current_application.applicants.where(family_member_id: applicant.family_member_id).first
              if current_applicant.present?
                applicant.retain_evidence_information(current_applicant)
              else
                build_history_for_new_applicant(applicant, current_application)
              end
            end

            Success(application)
          end

          # we need to add a history element indicating that the family member is added after the #{current year} application was determined
          def build_history_for_new_applicant(applicant, current_application)
            applicant.individual_market_eligibility.evidences.each do |evidence|
              evidence.build_verification_history(
                'no_matching_applicant',
                "family member is added after the #{current_application.assistance_year} application was determined, no prior evidence exists to retain on renewal",
                'system'
              )
            end
          end

          # Persists the application
          #
          # @param application [IndividualMarket::Application] The application to persist
          #
          # @return [Dry::Monads::Result] Success with the application or Failure with an error message
          def persist(application)
            application.save!
            Success(application)
          rescue StandardError => e
            Rails.logger.error("QHP Application - Failed to persist application due to #{e.message}, #{e.backtrace.join("\n")}")
            Failure("An error occurred while persisting the application: #{application.errors.full_messages.join(', ')}")
          end

          def regenerate_family_determination(application)
            family = application.family
            ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
          end
        end
      end
    end
  end
end
