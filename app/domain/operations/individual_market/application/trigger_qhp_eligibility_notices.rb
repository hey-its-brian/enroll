# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Application
      # send notice when IndividualMarket::Application QHP eligibility is determined
      class TriggerQhpEligibilityNotices
        include Dry::Monads[:do, :result]
        include EventSource::Command
        include EventSource::Logging

        # @param [IndividualMarket::Application] :application IndividualMarket::Application
        # @return [Dry::Monads::Result]
        def call(params)
          application = yield validate(params)
          event_key   = yield determine_application_event_key(application)
          app_entity  = yield build_app_entity(application, params[:application_entity])
          event       = yield build_event(event_key, app_entity)
          result      = yield publish(event)

          Success(result)
        end

        private

        def validate(params)
          return Failure('Missing Application') if params[:application].blank?

          application = params[:application]
          return Failure('Invalid Application') unless application.is_a?(::IndividualMarket::Application)
          return Failure("Application is not in determined state: #{application.current_state}") unless application.current_state == :determined

          Success(application)
        end

        # returns the event key for the appropriate eligibility determination
        # @param application [IndividualMarket::Application] the financial assistance application
        # @return [Dry::Monads::Result] Success with eligibility determination key
        # the logic here MAY need to be updated based on the actual eligibility determination logic
        def determine_application_event_key(application)
          eligibility_type = if application.applicants.all?(&:is_qhp_eligible)
                               :qhp_eligible
                             elsif application.applicants.none?(&:is_qhp_eligible)
                               :qhp_ineligible
                             else
                               :mixed_qhp_eligibilities
                             end

          event_key = "determined_#{eligibility_type}"
          Success(event_key)
        end

        # Builds the application entity required for verification services
        #
        # Uses the Fdsh BuildAndValidateApplicationPayload operation to create the
        # standardized application entity representation needed by verification services.
        #
        # @param application [FinancialAssistance::Application] The application to build an entity from
        # @return [Dry::Monads::Result::Success] Always returns success as the actual entity is stored in @application_entity
        def build_app_entity(application, entity = nil)
          result = if entity.present?
                     entity
                   else
                     Operations::IndividualMarket::Application::TransformToEntity.new.call(application)
                   end

          return Failure("Failed to build application entity for #{application.id}") if result.failure?

          result
        end

        def build_event(event_key, application_entity)
          result = event("events.individual_market.qhp.eligibilities.#{event_key}", attributes: application_entity.to_h)
          unless Rails.env.test?
            logger.info('-' * 100)
            logger.info(
              "Enroll Publisher to external systems (Polypress),
              event_key: events.individual_market.qhp.eligibilities.#{event_key}, attributes: #{application_entity.to_h}, result: #{result}"
            )
            logger.info('-' * 100)
          end
          result
        end

        def publish(event)
          Success(event.publish)
        end
      end
    end
  end
end
