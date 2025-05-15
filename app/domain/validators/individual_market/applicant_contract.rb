# frozen_string_literal: true

module Validators
  module IndividualMarket
    # Contract for validating Individual Market Applicant attributes
    class ApplicantContract < Dry::Validation::Contract
      params do
        required(:family_member_id).filled(Types::Bson)
        required(:is_primary_applicant).filled(:bool)
        required(:address_same_as_primary).filled(:bool)
        required(:is_applying_coverage).filled(:bool)
        optional(:is_homeless).maybe(:bool)
        optional(:is_temporarily_out_of_state).maybe(:bool)
        optional(:age_off_excluded).maybe(:bool)
        optional(:addresses).maybe(:array)

        required(:person_name).hash do
          required(:given_name).filled(:string)
          required(:family_name).filled(:string)
          optional(:middle_name).maybe(:string)
          optional(:name_pfx).maybe(:string)
          optional(:name_sfx).maybe(:string)
          optional(:alternate_name).maybe(:string)
        end

        required(:demographics).hash do
          optional(:encrypted_ssn).maybe(:string)
          optional(:no_ssn).maybe(:bool)
          required(:dob).filled(:date)
          required(:gender).filled(:string)
          optional(:ethnicity).array(:string)
          optional(:race).maybe(:string)
          optional(:is_incarcerated).maybe(:bool)
          optional(:is_physically_disabled).maybe(:bool)
          optional(:indian_tribe_member).maybe(:bool)
          optional(:tribal_id).maybe(:string)
          optional(:tribal_name).maybe(:string)
          optional(:tribal_state).maybe(:string)
          optional(:language_code).maybe(:string)
          optional(:tribe_codes).array(:string)
          optional(:citizen_status).maybe(:string)
        end

        optional(:immigration_information).hash do
          optional(:subject).maybe(:string)
          optional(:alien_number).maybe(:string)
          optional(:i94_number).maybe(:string)
          optional(:visa_number).maybe(:string)
          optional(:passport_number).maybe(:string)
          optional(:sevis_id).maybe(:string)
          optional(:naturalization_number).maybe(:string)
          optional(:receipt_number).maybe(:string)
          optional(:citizenship_number).maybe(:string)
          optional(:card_number).maybe(:string)
          optional(:country_of_citizenship).maybe(:string)
          optional(:expiration_date).maybe(:date)
          optional(:issuing_country).maybe(:string)
          optional(:description).maybe(:string)
        end

        required(:eligibilities).array(:hash) do
          required(:key).filled(:symbol)
          required(:title).filled(:string)
        end
      end

      rule(:addresses).each do
        if key? && value
          if value.is_a?(Hash)
            result = ::Validators::AddressContract.new.call(value)
            key.failure(text: "invalid address", error: result.errors.to_h) if result&.failure?
          else
            key.failure(text: "invalid addresses. Expected a hash.")
          end
        end
      end

    end
  end
end
