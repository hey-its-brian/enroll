# frozen_string_literal: true

module Operations
  module IndividualMarket
    module Application
      # This operation handles copying an individual market application.
      class Copy
        include Dry::Monads[:result, :do]

        # @param application [::IndividualMarket::Application] The application to copy
        # @param origin [String] The origin of the application, must be one of IndividualMarket::Application::ORIGIN_KINDS
        # @param generation_reason [String] The reason for generating the application, must be one of IndividualMarket::Application::GENERATION_REASONS
        # @param assistance_year [String, nil] The assistance year, optional
        #
        # @return [Dry::Monads::Result] Returns a Success with the copied application or a Failure with an error message
        def call(application:, origin:, generation_reason:, assistance_year: nil)
          application, origin, generation_reason, _assistance_year = yield validate_application(application, origin, generation_reason, assistance_year)
          new_application = yield generate_application(application.family_id, origin, generation_reason, assistance_year)
          new_application = yield persist(application, new_application)

          Success(new_application)
        end

        private

        # Validates the application, origin, and generation reason.
        #
        # @param application [::IndividualMarket::Application] The application to validate
        # @param origin [String] The origin of the application
        # @param generation_reason [String] The reason for generating the application
        # @param assistance_year [String, nil] The assistance year, optional
        #
        # @return [Dry::Monads::Result] Returns a Success with the validated parameters or a Failure with an error message
        def validate_application(application, origin, generation_reason, assistance_year)
          return Failure("Invalid application type: #{application.class.name}") unless application.is_a?(::IndividualMarket::Application)
          copyable_states = ::IndividualMarket::Application::COPYABLE_STATES
          return Failure("Application cannot be copied as it is not in one of the #{copyable_states.join(', ')} states") if copyable_states.exclude?(application.current_state)

          Success([application, origin, generation_reason])
        end

        # Builds the new application based on the Family's latest composition.
        #
        # @param family_id [String] The ID of the family from which the new application is being built
        # @param origin [String] The origin of the application
        # @param generation_reason [String] The reason for generating the application
        # @param assistance_year [String, nil] The assistance year, optional
        #
        # @return [Dry::Monads::Result] Returns a Success with the new application or a Failure with an error message
        def generate_application(family_id, origin, generation_reason, assistance_year)
          ::Operations::IndividualMarket::GenerateApplication.new.call(
            {
              assistance_year: assistance_year,
              family_id: family_id,
              generation_reason: generation_reason,
              origin: origin,
              renewal: false
            }
          )
        end

        # Persists the new application to the database.
        #
        # @param application [::IndividualMarket::Application] The original application
        # @param new_application [::IndividualMarket::Application] The new application to persist
        #
        # @return [Dry::Monads::Result] Returns a Success with the persisted application or a Failure with an error message
        def persist(application, new_application)
          new_application.predecessor_id = application.id

          if new_application.valid?
            new_application.save!
            Success(new_application)
          else
            Failure("Failed to persist new application: #{new_application.errors.full_messages.join(', ')}")
          end
        rescue StandardError => e
          Failure("Failed to persist new application: #{e.message}")
        end
      end
    end
  end
end
