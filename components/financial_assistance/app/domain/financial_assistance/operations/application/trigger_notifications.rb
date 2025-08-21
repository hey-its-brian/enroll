# frozen_string_literal: true

module FinancialAssistance
  module Operations
    module Application
      # Class to trigger notifications for financial assistance application with specific criteria
      class TriggerNotifications
        include Dry::Monads[:do, :result]
        include EventSource::Command

        # Triggers notifications for the application and its entity.
        def call(params)
          application, entity = yield validate(params)
          _triggered          = yield trigger_totally_ineligible_notice(application, entity)

          Success('All eligible notifications have been triggered successfully.')
        end

        private

        # Validates the input parameters for triggering notifications.
        #
        # @param params [Hash] The input parameters
        # @option params [FinancialAssistance::Application] :application The application to trigger notifications for
        # @option params [::AcaEntities::MagiMedicaid::Application] :application_entity The application entity that gets published as a payload
        #
        # @return [Dry::Monads::Result]
        def validate(params)
          return Failure('Application is expected to be of type FinancialAssistance::Application.') unless params[:application].is_a?(FinancialAssistance::Application)
          return Failure('Application is expected to be determined to trigger any notifications.') unless params[:application].determined?
          return Failure('Application entity is expected to be of type AcaEntities::MagiMedicaid::Application.') unless params[:application_entity].is_a?(::AcaEntities::MagiMedicaid::Application)

          Success([params[:application], params[:application_entity]])
        end

        # Triggers the totally ineligible notice for the application and its entity.
        #
        # @param application [FinancialAssistance::Application] The application to trigger notifications for
        # @param entity [::AcaEntities::MagiMedicaid::Application] The application entity that gets published as a payload
        #
        # @return [Dry::Monads::Result]
        def trigger_totally_ineligible_notice(application, entity)
          if eligible_for_totally_ineligible_notice?(application)
            event(
              'events.families.notices.faa_totally_ineligible_notice.requested',
              attributes: entity.to_h
            ).success.publish

            Success('Totally ineligible notice triggered successfully.')
          else
            Success('No notifications were triggered as the application is not eligible for any notification.')
          end
        end

        # Checks if the application is eligible for the totally ineligible notice.
        #
        # @param application [FinancialAssistance::Application] The application to check
        #
        # @return [Boolean]
        def eligible_for_totally_ineligible_notice?(application)
          FinancialAssistanceRegistry.feature_enabled?(:totally_ineligible_notice) && application.any_applicants_totally_ineligible?
        end
      end
    end
  end
end
