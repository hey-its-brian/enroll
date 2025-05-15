# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Applicant
      # Operation to build an Individual Market Applicant entity
      # This class validates applicant attributes and constructs a new applicant entity
      # Uses dry-monads for result handling and validation
      #
      # @example
      #   result = Build.new.call(params: applicant_params)
      #   if result.success?
      #     applicant = result.success
      #   else
      #     errors = result.failure
      #   end
      #
      # @see Validators::IndividualMarket::ApplicantContract
      # @see Entities::IndividualMarket::Applicant
      class Build
        include Dry::Monads[:do, :result]

        # @param [ Hash ] params Applicant Attributes
        # @return [FinancialAssistance::Entities::Applicant ] applicant Applicant
        def call(params:)
          values     = yield validate(params)
          applicant  = yield build(values)

          Success(applicant)
        end

        private

        def validate(params)
          # switch to use contract from aca_entities
          result = ::Validators::IndividualMarket::ApplicantContract.new.call(params)
          if result.success?
            Success(result.to_h)
          else
            Failure(result.errors.to_h)
          end
        end

        def build(values)
          # switch to use entity from aca_entities
          applicant_entity = ::Entities::IndividualMarket::Applicant.new(values)
          Success(applicant_entity)
        end
      end
    end
  end
end
