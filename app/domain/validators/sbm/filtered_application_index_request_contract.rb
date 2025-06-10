# frozen_string_literal: true

module Validators
  module Sbm
    # Validates parameters used to query FAA applications and QHP applications using filter criteria.
    class FilteredApplicationIndexRequestContract < Dry::Validation::Contract
      params do
        required(:family_id).filled(Types::Bson)
        optional(:filter_year).maybe(:integer)
      end
    end
  end
end
