# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    # This class constructs individual_market_applicant params_hash from a family member.
    # It handles the parsing of person attributes, demographics, and eligibility information.
    class ParseApplicant
      include Dry::Monads[:do, :result, :try]

      # Parses a family member into an applicant params hash
      # @param [ Hash ] params containing family_member
      # @return [ Result<Hash> ] Success with applicant params or Failure with error message
      def call(params)
        values = yield validate(params)
        applicant_hash = yield parse_family_member(values[:family_member])

        Success(applicant_hash)
      end

      private

      def validate(params)
        return Failure('Given family member is not a valid object') unless params[:family_member].is_a?(::FamilyMember)
        return Failure('Given family member does not have a matching person') unless params[:family_member].person.present?

        Success(params)
      end

      def parse_family_member(family_member)
        Try do
          applicant_params = person_attributes(family_member).merge(
            family_member_id: family_member.id,
            is_primary_applicant: family_member.is_primary_applicant,
            address_same_as_primary: address_same_as_primary?(family_member),
            is_applying_coverage: family_member.person.consumer_role&.is_applying_coverage,
            age_off_excluded: family_member.person&.age_off_excluded,
            contact_method: family_member.person.consumer_role&.contact_method,
            language_preference: family_member.person.consumer_role&.language_preference
          )
          applicant_params
        end.or(Failure("Could not build applicant params for family member with id: #{family_member&.id}"))
      end

      # Builds complete person attributes hash including name, demographics, and other information
      # @param [FamilyMember] family_member The family member to parse
      # @return [Hash] Complete person attributes
      def person_attributes(family_member)
        person = family_member.person
        {
          person_name: person_name_attributes(person),
          demographics: demographics_attributes(person),
          immigration_information: immigration_information_attributes(person.consumer_role, person&.immigration_doc_statuses),
          eligibilities: eligibilities_attributes,
          addresses: construct_address_fields(person.addresses),
          is_homeless: person.is_homeless,
          phones: construct_phone_fields(person.phones),
          emails: construct_email_fields(person.emails)
        }
      end

      def person_name_attributes(person)
        {
          given_name: person.first_name,
          middle_name: person.middle_name,
          family_name: person.last_name,
          name_pfx: person.name_pfx,
          name_sfx: person.name_sfx,
          alternate_name: person.alternate_name
        }
      end

      def demographics_attributes(person)
        {
          encrypted_ssn: person.encrypted_ssn,
          no_ssn: ActiveModel::Type::Boolean.new.cast(person.no_ssn),
          dob: person.dob,
          gender: person.gender,
          ethnicity: person.ethnicity,
          race: person.race,
          is_incarcerated: person.is_incarcerated,
          is_physically_disabled: person.is_disabled,
          indian_tribe_member: person.indian_tribe_member,
          tribal_id: person.tribal_id,
          tribal_name: person.tribal_name,
          tribal_state: person.tribal_state,
          tribe_codes: person.tribe_codes,
          citizen_status: person.citizen_status,
          language_code: person.language_code
        }
      end

      def immigration_information_attributes(consumer_role, doc_statuses)
        return {} unless consumer_role.active_vlp_document
        vlp_object = consumer_role.active_vlp_document
        vlp_attrs = vlp_object.attributes.symbolize_keys.slice(:alien_number,
                                                               :i94_number,
                                                               :visa_number,
                                                               :passport_number,
                                                               :sevis_id,
                                                               :naturalization_number,
                                                               :receipt_number,
                                                               :citizenship_number,
                                                               :card_number,
                                                               :country_of_citizenship,
                                                               :expiration_date,
                                                               :issuing_country)
        vlp_attrs.merge!({expiration_date: vlp_attrs[:expiration_date].strftime("%d/%m/%Y")}) if vlp_attrs[:expiration_date].present?
        vlp_attrs.merge!({subject: vlp_object[:subject], description: vlp_object[:description]})
        vlp_attrs.merge!({immigration_doc_statuses: doc_statuses}) if doc_statuses.present?
        vlp_attrs
      end

      def eligibilities_attributes
        [individual_market_eligibility_attributes]
      end

      def individual_market_eligibility_attributes
        {
          _type: 'Eligibilities::V3::IndividualMarketEligibility',
          key: :individual_market_eligibility,
          title: "Individual Market Eligibility"
        }
      end

      # Determines if the family member's address matches the primary person's address
      # @param [FamilyMember] family_member The family member to check
      # @return [Boolean] true if addresses match or false if they don't
      def address_same_as_primary?(family_member)
        return false if family_member.is_primary_applicant?

        family = family_member.family
        dependent = family_member.person
        primary = family.primary_person

        compare_address_keys = address_comparison_keys
        dependent_addresses = slice_attributes(dependent, compare_address_keys)
        primary_addresses = slice_attributes(primary, compare_address_keys)

        return false if dependent_addresses.empty? || primary_addresses.empty?

        dependent_addresses == primary_addresses
      end

      # Gets the list of address keys to compare
      # @return [Array<String>] List of address attributes to compare
      def address_comparison_keys
        keys = ["address_1", "address_2", "city", "state", "zip", "is_homeless", "is_temporarily_out_of_state"]
        keys << "county" if EnrollRegistry.feature_enabled?(:display_county)
        keys
      end

      # Safely extracts address attributes from a person
      # @param [Person] person The person whose attributes to slice
      # @param [Array<String>] compare_address_keys The keys to extract
      # @return [Array<Hash>] Array of address attributes, excluding nil values
      def slice_attributes(person, compare_address_keys)
        [
          person.attributes.slice(*compare_address_keys),
          person.home_address&.attributes&.slice(*compare_address_keys)
        ].compact
      end

      # Constructs association fields for a record
      # @param [Array<Mongoid::Document>] records The records to construct association fields for
      # @return [Array<Hash>] Array of association fields
      def construct_address_fields(records)
        records.collect do |record|
          record.attributes.slice(
            "kind",
            "address_1",
            "address_2",
            "city",
            "state",
            "zip",
            "county"
          ).symbolize_keys
        end
      end

      # Constructs phone fields for a record
      # @param [Array<Mongoid::Document>] records The records to construct phone fields for
      # @return [Array<Hash>] Array of phone fields
      def construct_phone_fields(records)
        records.collect do |record|
          record.attributes.slice(
            "kind",
            "number",
            "country_code",
            "area_code",
            "number",
            "extension",
            "full_phone_number",
            "primary"
          ).symbolize_keys
        end
      end

      # Constructs email fields for a record
      # @param [Array<Mongoid::Document>] records The records to construct email fields for
      # @return [Array<Hash>] Array of email fields
      def construct_email_fields(records)
        records.collect do |record|
          record.attributes.slice(
            "kind",
            "address"
          ).symbolize_keys
        end
      end
    end
  end
end
