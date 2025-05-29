# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Applicant
      # This operation is used to destroy an applicant from an application
      # and remove associated relationships
      class Destroy
        include Dry::Monads[:do, :result]

        def call(applicant)
          applicant = yield validate(applicant)
          result    = yield destroy_applicant(applicant)

          Success(result)
        end

        private

        def validate(applicant)
          return Failure("Given input: #{applicant} is not a valid IndividualMarket::Applicant.") unless applicant.is_a?(::IndividualMarket::Applicant)
          return Failure("Given applicant with id: #{applicant.id} is a primary applicant, cannot be destroyed/deleted.") if applicant.is_primary_applicant
          @application = applicant.application
          return Failure("The application: #{@application.id} for given applicant with id: #{applicant.id} has already been submitted, applicant cannot be destroyed/deleted.") unless @application.current_state == :initial

          Success(applicant)
        end

        def destroy_applicant(applicant)
          @application.relationships.where(source_id: applicant.id).destroy_all
          applicant.destroy!
          @application.reload
          Success("Successfully destroyed applicant with id: #{applicant.id}.")
        end
      end
    end
  end
end
