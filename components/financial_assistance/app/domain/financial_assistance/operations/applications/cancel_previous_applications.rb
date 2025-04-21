# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module FinancialAssistance
  module Operations
    module Applications
      # This class is responsible for cancelling all the previous draft applications of the family for the given application for the same assistance year as the new application.
      class CancelPreviousApplications
        include Dry::Monads[:do, :result]

        # @param [Hash] opts The options to cancel previous applications.
        # @option opts [FinancialAssistance::Application] :application (required)
        # @return [Dry::Monads::Result]
        def call(params)
          application         = yield validate(params)
          draft_applications  = yield fetch_draft_applications(application)
          cancelled_result    = yield cancel(application, draft_applications)

          Success(cancelled_result)
        end

        private

        # Validates the input parameters
        # @param [Hash] params Input parameters
        # @option params [FinancialAssistance::Application] :application The application object
        # @return [Dry::Monads::Result::Success] Success monad with application if valid
        # @return [Dry::Monads::Result::Failure] Failure monad with error message if invalid
        def validate(params)
          application = params[:application]

          if application.is_a?(FinancialAssistance::Application)
            Success(application)
          else
            Failure('Invalid parameters: application is required.')
          end
        end

        # Fetches all draft applications for the same family excluding the current application
        # @param [FinancialAssistance::Application] application The new application
        # @return [Dry::Monads::Result::Success] Success monad with collection of applications if found
        # @return [Dry::Monads::Result::Failure] Failure monad with error message if family_id is missing
        def fetch_draft_applications(application)
          if application.family_id.blank?
            Failure('Missing family_id for application to fetch previous applications')
          else
            Success(
              ::FinancialAssistance::Application.where(
                aasm_state: 'draft',
                family_id: application.family_id,
                :id.ne => application.id
              )
            )
          end
        end

        # Cancels all previous draft applications for the family
        # @param [FinancialAssistance::Application] new_draft_application The newly created application
        # @param [Mongoid::Criteria] draft_applications Collection of applications to be cancelled
        # @return [Dry::Monads::Result::Success] Success monad with message indicating cancelled applications
        def cancel(new_draft_application, draft_applications)
          draft_applications.each do |app|
            app.cancel!(
              {
                reason: "Cancelled by the system due to new application: #{new_draft_application.hbx_id} creation",
                comment: "Cancelled by the system due to new application: #{new_draft_application.hbx_id} creation"
              }
            )
          rescue StandardError => e
            Rails.logger.error(
              "FAOACPA - Failed to cancel previous draft applications: #{e.message} for application: #{app.hbx_id}"
            )
          end

          Success("Cancelled all previous draft applications with hbx_ids: #{draft_applications.pluck(:hbx_id).join(', ')}")
        end
      end
    end
  end
end
