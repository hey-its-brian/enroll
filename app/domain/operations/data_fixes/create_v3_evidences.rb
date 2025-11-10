# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# ::Operations::DataFixes::CreateIndividualMarketEvidences.new.call({application_hbx_id: application_hbx_id})
module Operations
  module DataFixes
    # This is an operation inherited by other data fix operations that create v3 evidences.
    class CreateV3Evidences
      include Dry::Monads[:do, :result]

      def call(params)
        application_hbx_id = yield validate(params)
        @application = yield find_application(application_hbx_id)
        yield validate_application(@application)
      end

      def validate(params)
        return Failure("application_hbx_id is missing") unless params[:application_hbx_id].present?
        return Failure("action setting not specified") unless params[:action].present?
        return Failure("action setting invalid") unless ['data_fix', 'report'].include?(params[:action])
        @report = params[:action] == 'report'

        Success(params[:application_hbx_id])
      end

      def find_application(application_hbx_id)
        application = ::FinancialAssistance::Application.where(hbx_id: application_hbx_id).first
        return Failure('Application not found') unless application.present?

        latest_application = application.family.latest_determined_faa_application
        return Failure('Application is not latest determined application for family') unless latest_application.hbx_id == application.hbx_id

        Success(application)
      end

      def validate_application(application)
        return Failure("Application should be in determined state") unless application.determined?

        Success(application)
      end
    end
  end
end
