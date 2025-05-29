# frozen_string_literal: true

module Entities
  module IndividualMarket
    # Entity representing an Individual Market Applicant
    class ApplicantCandidate < Dry::Struct
      transform_keys(&:to_sym)

      # Top-level attributes
      attribute :family_member_id, Types::Bson.optional.meta(omittable: true)
      attribute :is_primary_applicant, Types::Bool
      attribute :address_same_as_primary, Types::Bool
      attribute :is_applying_coverage, Types::Bool
      attribute :is_homeless, Types::Bool.optional.meta(omittable: true)
      attribute :is_temporarily_out_of_state, Types::Bool.optional.meta(omittable: true)
      attribute :age_off_excluded, Types::Bool.optional.meta(omittable: true)

      # Nested PersonName attributes
      attribute :person_name do
        attribute :given_name, Types::String
        attribute :family_name, Types::String
        attribute :middle_name, Types::String.optional.meta(omittable: true)
        attribute :name_pfx, Types::String.optional.meta(omittable: true)
        attribute :name_sfx, Types::String.optional.meta(omittable: true)
        attribute :alternate_name, Types::String.optional.meta(omittable: true)
      end

      # Nested Demographics attributes
      attribute :demographics do
        attribute :encrypted_ssn, Types::String.optional.meta(omittable: true)
        attribute :no_ssn, Types::Bool.optional.meta(omittable: true)
        attribute :dob, Types::Date
        attribute :gender, Types::String
        attribute :ssn, Types::String.optional.meta(omittable: true)
        attribute :ethnicity, Types::Array.of(Types::String).optional.meta(omittable: true)
        attribute :race, Types::String.optional.meta(omittable: true)
        attribute :is_incarcerated, Types::Bool.optional.meta(omittable: true)
        attribute :is_physically_disabled, Types::Bool.optional.meta(omittable: true)
        attribute :indian_tribe_member, Types::Bool.optional.meta(omittable: true)
        attribute :tribal_id, Types::String.optional.meta(omittable: true)
        attribute :tribal_name, Types::String.optional.meta(omittable: true)
        attribute :tribal_state, Types::String.optional.meta(omittable: true)
        attribute :language_code, Types::String.optional.meta(omittable: true)
        attribute :tribe_codes, Types::Array.of(Types::String).optional.meta(omittable: true)
        attribute :citizen_status, Types::String.optional.meta(omittable: true)
      end

      # Nested Immigration Information attributes
      attribute? :immigration_information do
        attribute :subject, Types::String.optional.meta(omittable: true)
        attribute :alien_number, Types::String.optional.meta(omittable: true)
        attribute :i94_number, Types::String.optional.meta(omittable: true)
        attribute :visa_number, Types::String.optional.meta(omittable: true)
        attribute :passport_number, Types::String.optional.meta(omittable: true)
        attribute :sevis_id, Types::String.optional.meta(omittable: true)
        attribute :naturalization_number, Types::String.optional.meta(omittable: true)
        attribute :receipt_number, Types::String.optional.meta(omittable: true)
        attribute :citizenship_number, Types::String.optional.meta(omittable: true)
        attribute :card_number, Types::String.optional.meta(omittable: true)
        attribute :country_of_citizenship, Types::String.optional.meta(omittable: true)
        attribute :expiration_date, Types::Date.optional.meta(omittable: true)
        attribute :issuing_country, Types::String.optional.meta(omittable: true)
        attribute :description, Types::String.optional.meta(omittable: true)
      end

      # Addresses array
      attribute :addresses, Types::Array.of(Entities::Address).optional.meta(omittable: true)
      # Eligibilities array
      attribute :eligibilities, Types::Array do
        attribute :key, Types::Symbol
        attribute :title, Types::String
      end
    end
  end
end
