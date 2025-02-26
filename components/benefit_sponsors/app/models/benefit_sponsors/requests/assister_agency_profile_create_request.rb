# frozen_string_literal: true

require 'dry-initializer'
require 'dry-types'
require 'mail'

module BenefitSponsors
  module Requests
    class Address
      extend Dry::Initializer
      option :address_1, Dry::Types['coercible.string'], optional: true
      option :address_2, Dry::Types['coercible.string'], optional: true
      option :city, Dry::Types['coercible.string'], optional: true
      option :state, Dry::Types['coercible.string'], optional: true
      option :zip, Dry::Types['coercible.string'], optional: true
    end

    class Phone
      extend Dry::Initializer
      option :phone_area_code, Dry::Types['coercible.string'], optional: true
      option :phone_number, Dry::Types['coercible.string'], optional: true
      option :phone_extension, Dry::Types['coercible.string'], optional: true
    end

    class OfficeLocation
      extend Dry::Initializer
      option :kind, type: Dry::Types['coercible.string'], optional: true
      option :address, ->(args) { ::BenefitSponsors::Requests::Address.new(args) }, optional: true
      option :phone, ->(args) { ::BenefitSponsors::Requests::Phone.new(args) }, optional: true
    end

    # UsDateCoercer is a utility class that converts a date string in MM/DD/YYYY format to a Date object.
    # If the input string is invalid or cannot be parsed, it returns nil.
    class UsDateCoercer
      # Converts a date string in MM/DD/YYYY format to a Date object.
      #
      # @param string [String] the date string to be converted.
      # @return [Date, nil] the parsed Date object or nil if conversion fails.
      def self.coerce(string)
        return nil unless string.is_a?(String) && !string.strip.empty?

        Date.strptime(string, "%m/%d/%Y")
      rescue ArgumentError => e
        warn "Invalid date format: #{e.message}"
        nil
      end
    end

    class AssisterAgencyProfileCreateRequest
      extend Dry::Initializer

      option :legal_name, type: Dry::Types['coercible.string'], optional: true
      option :dba, type: Dry::Types['coercible.string'], optional: true
      option :assister_org_id, type: Dry::Types['coercible.string'], optional: true
      option :first_name, type: Dry::Types['coercible.string'], optional: true
      option :last_name, type: Dry::Types['coercible.string'], optional: true
      option :dob, type: ->(val) { UsDateCoercer.coerce(val) }, optional: true
      option :email, type: Dry::Types['coercible.string'], optional: true

      option :practice_area, type: Dry::Types['coercible.string'], optional: true
      option :accepts_new_clients, type: Dry::Types['params.bool'], optional: true
      option :evening_weekend_hours, type: Dry::Types['params.bool'], optional: true
      option :languages, type: Dry::Types['coercible.array'].of(Dry::Types['coercible.string']), optional: true
      option :address, ->(args) { ::BenefitSponsors::Requests::Address.new(args) }, optional: true
      option :phone, ->(args) { ::BenefitSponsors::Requests::Phone.new(args) }, optional: true

      option :office_locations, type: Dry::Types['coercible.array'].of(->(args) { ::BenefitSponsors::Requests::OfficeLocation.new(args) }), optional: true
    end
  end
end
