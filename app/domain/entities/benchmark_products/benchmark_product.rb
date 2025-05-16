# frozen_string_literal: true

module Entities
  module BenchmarkProducts
    class BenchmarkProduct < Dry::Struct
      attribute :data_source, Types::String.optional.meta(omittable: true)
      attribute :family_id, Types::Bson.optional.meta(omittable: true)
      attribute :application_id, Types::Bson.optional.meta(omittable: true)
      attribute :rating_address, RatingAddress.optional.meta(omittable: true)
      attribute :effective_date, Types::Date.meta(omittable: false)
      # Rating Address of the Primary Person of the Family or Primary Applicant of the Application
      attribute :primary_rating_address_id, Types::Bson.optional.meta(omittable: true)
      attribute :rating_area_id, Types::Bson.optional.meta(omittable: true)
      attribute :exchange_provided_code, Types::String.optional.meta(omittable: true)
      attribute :service_area_ids, Types::Array.of(Types::Bson).optional.meta(omittable: true)
      attribute :household_group_benchmark_ehb_premium, ::AcaEntities::Types::Money.optional.meta(omittable: true)
      attribute :origin, Types::String.optional.meta(omittable: true)

      attribute :households, Types::Array.of(Entities::BenchmarkProducts::Household).meta(omittable: false)
    end
  end
end
