# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module DataFixes
    # This operation is responsible for backfilling missing county information for person addresses.
    class BackfillPersonAddressCounties
      include Dry::Monads[:do, :result]

      def call(person_hbx_id:)
        primary_person = yield fetch_primary_person(person_hbx_id)
        _success = yield fix_county_for_address(primary_person)
        _success = yield fix_county_for_faa_applications(primary_person)

        Success(primary_person)
      end

      def fix_county_for_address(primary_person)
        primary_person.addresses.each do |address|
          next unless address.county == "Please provide a zip code" || address.county.blank?
          next unless address.zip.present?

          county = fetch_county(address.zip)
          address.set(county: county) if county.present?
        end

        Success(primary_person)
      end

      def fix_county_for_faa_applications(primary_person)
        family_id = primary_person.primary_family&.id
        return Success(primary_person) unless family_id

        applications = ::FinancialAssistance::Application.where(family_id: family_id)
        applications.each do |application|
          application.applicants.each do |applicant|
            applicant.addresses.each do |address|
              next unless address.county.blank? || address.county == "Please provide a zip code"
              next unless address.zip.present?

              county = fetch_county(address.zip)
              address.set(county: county)
            end
          end
        end

        Success(primary_person)
      end

      def fetch_county(zip)
        counties = BenefitMarkets::Locations::CountyZip
                   .where(zip: zip.slice(/\d{5}/))
                   .pluck(:county_name)
                   .uniq

        counties.present? ? counties.first : nil
      end

      private

      def fetch_primary_person(person_hbx_id)
        primary_person = Person.find_by(hbx_id: person_hbx_id)
        return Failure(:primary_person_not_found) unless primary_person
        Success(primary_person)
      rescue Mongoid::Errors::DocumentNotFound
        Failure(:primary_person_not_found)
      end
    end
  end
end