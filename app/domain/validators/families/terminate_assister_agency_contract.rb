# frozen_string_literal: true

module Validators
  module Families
    # Validator that validates assister agency term params.
    class TerminateAssisterAgencyContract < Dry::Validation::Contract

      params do
        required(:family_id).filled(Types::Bson)
        required(:assister_account_id).filled(Types::Bson)
        required(:terminate_date).filled(:date)
        optional(:notify_edi).maybe(:bool)
      end

      rule(:assister_account_id) do
        if key? && value
          result = Operations::Families::FindAssisterAgencyAccount.new.call({family_id: values[:family_id], assister_account_id: values[:assister_account_id]})
          key.failure(text: 'invalid assister_account_id', error: result.failure) if result&.failure?
        end
      end
    end
  end
end
