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
        #
        # @return [Dry::Monads::Result] Returns a Success with the copied application or a Failure with an error message
        def call(application:, origin:, generation_reason:, assistance_year: nil)
          application, origin, generation_reason, _assistance_year = yield validate_application(application, origin, generation_reason, assistance_year)
          copied_application                      = yield copy_application(application, origin, generation_reason)
          _cancelled                              = yield cancel_previous_applications(copied_application)

          Success(copied_application)
        end

        private

        # Validates the application, origin, and generation reason.
        #
        # @param application [::IndividualMarket::Application] The application to validate
        # @param origin [String] The origin of the application
        # @param generation_reason [String] The reason for generating the application
        #
        # @return [Dry::Monads::Result] Returns a Success with the validated parameters or a Failure with an error message
        def validate_application(application, origin, generation_reason, assistance_year)
          return Failure("Invalid application type: #{application.class.name}") unless application.is_a?(::IndividualMarket::Application)
          return Failure("Application cannot be copied as it is not in one of the #{::IndividualMarket::Application::COPYABLE_STATES.join(', ')} states") unless ::IndividualMarket::Application::COPYABLE_STATES.include?(application.current_state)
          return Failure(I18n.t('faa.errors.invalid_assistance_year_error')) if invalid_assistance_year?(assistance_year)
          return Failure("Invalid origin: #{origin}") if ::IndividualMarket::Application::ORIGIN_KINDS.exclude?(origin)
          return Failure("Invalid generation reason: #{generation_reason}") if ::IndividualMarket::Application::GENERATION_REASONS.exclude?(generation_reason)

          Success([application, origin, generation_reason])
        end

        # Validates the assistance year.
        #
        # @param assistance_year [String] The assistance year to validate
        #
        # @return [Boolean] Returns true if the assistance year is valid, false otherwise
        def invalid_assistance_year?(assistance_year)
          return false unless assistance_year.present?

          @assistance_year = assistance_year.to_i
          !assistance_year.to_s.match?(/\A\d+\z/)
        end

        # Copies the application and saves it.
        #
        # @param application [::IndividualMarket::Application] The application to copy
        # @param origin [String] The origin of the application
        # @param generation_reason [String] The reason for generating the application
        # @return [Dry::Monads::Result] Returns a Success with the copied application or a Failure with an error message
        def copy_application(application, origin, generation_reason)
          copy_params = {origin: origin, generation_reason: generation_reason}
          copy_params[:copy_year] = @assistance_year if @assistance_year.present?

          new_application = application.copy_application(**copy_params)

          if new_application.valid?
            begin
              new_application.save!
              Success(new_application)
            rescue StandardError => e
              Rails.logger.error("QHP Application - Copy of application with hbx_id: #{application.hbx_id} failed: #{e.message}")
              Failure("Unable to copy application: #{e.message}")
            end
          else
            Rails.logger.error("QHP Application - Copy failed validation: #{new_application.errors.full_messages.join(', ')}")
            Failure("Application copy failed validation: #{new_application.errors.full_messages.join(', ')}")
          end
        rescue StandardError => e
          Rails.logger.error("QHP Application - Copy operation failed for application with hbx_id: #{application.hbx_id} - Error: #{e.message}, Backtrace: #{e.backtrace.join("\n")}")
          Failure("Copy operation failed for application with hbx_id: #{application.hbx_id} - Error: #{e.message}")
        end

        def cancel_previous_applications(application)
          ::Operations::Sbm::Applications::CancelPreviousApplications.new.call(application: application)
        end
      end
    end
  end
end
