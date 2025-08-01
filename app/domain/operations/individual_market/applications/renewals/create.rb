# frozen_string_literal: true

module Operations
  module IndividualMarket
    module Applications
      module Renewals
        # Operation to create an individual market application for a given family and renewal year in initial state.
        class Create
          include Dry::Monads[:result, :do]
          include EventSource::Command

          FA_APP_STATES = %w[applicants_update_required income_verification_extension_required].freeze

          # Creates a renewal application for individual market applications
          #
          # @param family_id [String] the ID of the family for which to create the renewal application
          # @param renewal_year [Integer] the year for which the renewal application is created
          #
          # @return [Dry::Monads::Result] Success with the created application or Failure with an error message
          def call(family_id:, renewal_year:)
            family, renewal_year  = yield validate_inputs(family_id, renewal_year)
            _eligible             = yield check_eligibility(family, renewal_year)
            application           = yield create(family, renewal_year)
            event                 = yield build_event(application, family)
            _published            = yield publish_event(event)

            Success(application)
          end

          private

          # Validates the inputs for family ID and renewal year
          #
          # @param family_id [String] the ID of the family
          # @param renewal_year [Integer] the year for which the renewal application is created
          #
          # @return [Dry::Monads::Result] Success with family and renewal year or Failure with an error message
          def validate_inputs(family_id, renewal_year)
            family = Family.only(:_id).where(id: family_id).first
            return Failure("Family with id #{family_id} not found") unless family
            return Failure("Invalid renewal year: #{renewal_year}") unless renewal_year.is_a?(Integer)

            Success([family, renewal_year])
          end

          # Checks if the family is eligible for a renewal application
          #
          # @param family [Family] the family for which to check eligibility
          # @param renewal_year [Integer] the year for which the renewal application is created
          #
          # @return [Dry::Monads::Result] Success if eligible, Failure with an error message otherwise
          def check_eligibility(family, renewal_year)
            fa_applications = ::FinancialAssistance::Application.only(
              :assistance_year, :family_id, :aasm_state
            ).where(assistance_year: renewal_year, family_id: family.id)
            return Failure("Family with #{family.id} already has Financial Assistance application for the renewal year #{renewal_year}") if fa_applications.any? { |app| FA_APP_STATES.exclude?(app.aasm_state) }

            enrollments = HbxEnrollment.only(
              :aasm_state, :effective_on, :family_id, :kind
            ).individual_market.enrolled.current_year.where(family_id: family.id)
            return Failure("Family with #{family.id} does not have any effectuated enrollments") if enrollments.empty?

            Success(true)
          end

          # Generates a new application for the family for the renewal year
          #
          # @param family [Family] the family for which to create the renewal application
          # @param renewal_year [Integer] the year for which the renewal application is created
          #
          # @return [Dry::Monads::Result] Success with the created application or Failure with an error message
          def create(family, renewal_year)
            ::Operations::IndividualMarket::GenerateApplication.new.call(
              family: family,
              assistance_year: renewal_year,
              origin: :system,
              generation_reason: :renewal,
              renewal: true
            )
          end

          # Builds an event for the created application
          #
          # @param application [IndividualMarketApplication] the created application
          # @param family [Family] the family for which the application was created
          #
          # @return [Dry::Monads::Result] Success with the event or Failure with an error message
          def build_event(application, family)
            event(
              'events.individual_market.applications.renewal.submit_and_determine',
              attributes: { application_id: application.id.to_s, family_id: family.id.to_s }
            )
          end

          # Publishes the event to the event source
          #
          # @param event [EventSource::Event] the event to be published
          #
          # @return [Dry::Monads::Result] Success if the event was published, raises an error otherwise
          def publish_event(event)
            event.publish

            Success('Successfully published an event for submitting and determining renewal application')
          end
        end
      end
    end
  end
end
