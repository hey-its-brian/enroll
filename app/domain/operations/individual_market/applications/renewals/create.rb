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
            application           = yield build(family, renewal_year)
            application           = yield persist(application)
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
            family = ::Family.where(id: family_id).first
            return Failure("Family with id #{family_id} not found") unless family
            return Failure("Invalid renewal year: #{renewal_year}") unless renewal_year.is_a?(Integer)

            Success([family, renewal_year])
          end

          # Finds or creates a renewal application for the family for the renewal year
          #
          # @param family [Family] the family for which to create the renewal application
          # @param renewal_year [Integer] the year for which the renewal application is created
          #
          # @return [Dry::Monads::Result] Success with the created application or Failure with an error message
          def build(family, renewal_year)
            @renewal_draft_application = family.qhp_applications_for_year(renewal_year).first
            if @renewal_draft_application
              return Success(@renewal_draft_application) if @renewal_draft_application.is_initial?
              return Failure("Family with #{family.id} already has a non-initial QHP application for the renewal year #{renewal_year}")
            end

            ::Operations::IndividualMarket::GenerateApplication.new.call(
              family: family,
              assistance_year: renewal_year,
              origin: :system,
              generation_reason: :renewal,
              renewal: true
            )
          end

          # Persists the generated application in the Database
          #
          # @param application [IndividualMarketApplication] the application to persist
          #
          # @return [Dry::Monads::Result] Success with the persisted application or Failure with an error message
          def persist(application)
            return Success(application) if @renewal_draft_application

            if application.valid?
              application.save!
              Success(application)
            else
              Failure("Failed to persist application: #{application.errors.full_messages.join(', ')}")
            end
          rescue StandardError => e
            Failure("Failed to persist application: #{e.message}, backtrace: #{e.backtrace.join(', ')}")
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
