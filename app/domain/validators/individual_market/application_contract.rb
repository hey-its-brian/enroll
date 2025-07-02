# frozen_string_literal: true

module Validators
  module IndividualMarket
    # Contract for validating Individual Market Application attributes
    # Uses dry-validation to define and enforce validation rules for application data
    #
    # Validates:
    # - family_id: Must be a valid BSON ObjectId and reference an existing family
    # - assistance_year: Must be a valid integer
    # - origin_source: Must be a valid symbol representing the application's source
    # - generation_reason: Must be a valid symbol representing why the application was generated
    # - applicants: Must be an array of valid applicant hashes
    #
    # @example
    #   contract = Application.new
    #   result = contract.call(
    #     family_id: BSON::ObjectId.new,
    #     assistance_year: 2024,
    #     origin_source: :aca_individual,
    #     generation_reason: :initial_enrollment,
    #     applicants: [{...}]
    #   )
    #
    #   if result.success?
    #     valid_data = result.to_h
    #   else
    #     errors = result.errors.to_h
    #   end
    #
    # @see Operations::Families::Find
    # @see Validators::IndividualMarket::ApplicantCandidateContract
    class ApplicationContract < Dry::Validation::Contract

      params do
        required(:family_id).filled(Types::Bson)
        required(:assistance_year).filled(Types::Integer)
        required(:origin).filled(:symbol)
        required(:generation_reason).filled(:symbol)
        required(:applicants).array(:hash)
        optional(:submitted_at).maybe(:date_time)
        optional(:current_state).maybe(:symbol)
      end

      rule(:family_id) do
        if key? && value
          result = Operations::Families::Find.new.call(id: value)
          key.failure(text: 'invalid family_id', error: result.errors.to_h) if result&.failure?
        end
      end

      rule(:applicants).each do
        if key? && value
          if value.is_a?(Hash)
            result = ::Validators::IndividualMarket::ApplicantCandidateContract.new.call(value)
            key.failure(text: "invalid applicant", error: result.errors.to_h) if result&.failure?
          else
            key.failure(text: "invalid applicant. Expected a hash.")
          end
        end
      end
    end
  end
end
