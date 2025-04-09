# frozen_string_literal: true

module ContactProfile
  # Represents a work phone number with its components
  #
  # @example Create a new work phone
  #   work = ContactProfile::WorkPhone.new(
  #     country_code: '1',
  #     area_code: '555',
  #     number: '1234567',
  #     primary: true
  #   )
  class WorkPhone
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [r] phone
    #   @return [ContactProfile::Phone] The parent phone document this work phone is embedded in
    embedded_in :phone, class_name: 'ContactProfile::Phone'

    # @!attribute [rw] country_code
    #   @return [String] The country code of the phone number
    field :country_code, type: String, default: ''

    # @!attribute [rw] area_code
    #   @return [String] The area code of the phone number
    field :area_code, type: String, default: ''

    # @!attribute [rw] number
    #   @return [String] The main part of the phone number
    field :number, type: String, default: ''

    # @!attribute [rw] extension
    #   @return [String] The extension of the phone number, if any
    field :extension, type: String, default: ''

    # @!attribute [rw] primary
    #   @return [Boolean] Flag indicating if this is the primary work phone
    field :primary, type: Boolean
  end
end
