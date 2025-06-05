# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    # In progress operation to submit an individual market application
    class SubmitAndDetermineApplication
      include Dry::Monads[:do, :result]

      def call(application)
        application = yield validate(application)
        application = yield submit_application(application)
        _applicants = yield determine_applicants(application)
        # create evidences for each applicant
        # create or update family members
        # deactive current tax household
        # create new tax household
        # update family determination
        determined_application = yield determine_application(application)
        Success(determined_application)
      end

      private

      def validate(application)
        return Failure('Invalid application type. Expected IndividualMarket::Application.') unless application.is_a?(::IndividualMarket::Application)
        return Failure('Invalid application has not been submitted.') unless application.current_state == :initial
        return Failure("Invalid application due to #{application.errors.full_messages.join(', ')}") unless application.valid?
        return Failure("Invalid Family for given application with hbx_id: #{application.hbx_id}") unless application.family.is_a?(::Family)
        Success(application)
      end

      def submit_application(application)
        application.submit
        if application.save
          Success(application.reload)
        else
          Failure("Failed to submit application due to #{application.errors.full_messages.join(', ')}")
        end
      end

      def determine_applicants(application)
        applicants_results = application.applicants.map do |applicant|
          Operations::IndividualMarket::Applicant::Determine.new.call({application: application, applicant: applicant})
        end
        Success(applicants_results)
      end

      def generate_evidences(_application)
        # TODO: Implement this once the FAA pattern is established
        Success([])
      end

      def determine_application(application)
        application.determine
        if application.save
          Success(application.reload)
        else
          Failure("Failed to determine application due to #{application.errors.full_messages.join(', ')}")
        end
      end

    end
  end
end