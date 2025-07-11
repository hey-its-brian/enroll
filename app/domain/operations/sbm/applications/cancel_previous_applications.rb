# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Sbm
    module Applications
      # this class is responsible for cancelling previous draft applications of the family for the given application for the same assistance year as the new application.
      class CancelPreviousApplications
        include Dry::Monads[:do, :result]

        # @param [Hash] params
        # @option params [::IndividualMarket::Application, ::FinancialAssistance::Application] :application
        # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure]
        def call(params)
          application = yield validate(params)
          draft_applications = yield fetch_draft_applications(application)
          cancelled_result = yield cancel(application, draft_applications)

          Success(cancelled_result)
        end

        private

        # @param [Hash] params
        # @option params [::IndividualMarket::Application, ::FinancialAssistance::Application] :application
        # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure]
        def validate(params)
          application = params[:application]
          return Failure('Invalid parameters: application is required.') unless application.is_a?(::IndividualMarket::Application) || application.is_a?(::FinancialAssistance::Application)
          return Failure('Missing family_id for application to fetch previous applications') if application.family_id.blank?
          return Failure('Missing assistance_year for application to fetch previous applications') if application.assistance_year.blank?
          Success(application)
        end

        def fetch_draft_applications(application)
          # assistance years can't be nil for ivl applications but leaving it here to make sure
          # the expectation is there in case that changes in the future
          draft_ivl_applications = ::IndividualMarket::Application.where(
            family_id: application.family_id,
            current_state: :initial,
            :assistance_year.in => [application.assistance_year, nil]
          )
          draft_fa_applications = ::FinancialAssistance::Application.where(
            aasm_state: 'draft',
            family_id: application.family_id,
            :assistance_year.in => [application.assistance_year, nil]
          )
          draft_applications = draft_ivl_applications + draft_fa_applications
          Success(draft_applications&.compact_blank)
        end

        def cancel(application, draft_applications)
          draft_applications.each do |draft_application|
            next if draft_application == application
            draft_application.cancel!(
              reason: "Cancelled by the system due to new application: #{application.hbx_id} creation",
              comment: "Cancelled by the system due to new application: #{application.hbx_id} creation"
            )
          rescue StandardError => e
            Rails.logger.error("Error cancelling previous draft applications: #{e.message}")
          end
          Success("Cancelled draft applications with hbx_ids: #{draft_applications.pluck(:hbx_id).join(', ')}")
        end
      end
    end
  end
end
