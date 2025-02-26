# frozen_string_literal: true

module Validators
  module Families
    # Validator that validates assister agency hire params.
    class HireAssisterAgencyContract < Dry::Validation::Contract

      params do
        required(:family_id).filled(Types::Bson)
        optional(:current_assister_account_id).maybe(Types::Bson)
        required(:assister_role_id).filled(Types::Bson)
        optional(:terminate_date).maybe(:date)
        required(:start_date).maybe(:date_time)
      end

      rule(:assister_role_id) do
        if key? && value
          result = ::Operations::AssisterRole::Find.new.call(values[:assister_role_id])
          key.failure(text: 'invalid assister_role_id', error: result.failure) if result&.failure?
          key.failure(text: 'missing benefit_sponsors_assister_agency_profile_id in assister role', error: result) if result&.success&.benefit_sponsors_assister_agency_profile_id.blank?
          key.failure(text: 'Cant Hire Assister with imported state', error: result) if result&.success&.imported?
        end
      end

      rule(:current_assister_account_id) do
        if key? && values[:current_assister_account_id].present?
          result = ::Operations::Families::FindAssisterAgencyAccount.new.call({family_id: values[:family_id], assister_account_id: values[:current_assister_account_id]})
          key.failure(text: 'invalid assister_account_id', error: result.failure) if result&.failure?
        end
      end
    end
  end
end
