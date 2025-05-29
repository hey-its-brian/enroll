# frozen_string_literal: true

module Locations
  # The Address class represents a physical address associated with an entity.
  # It is used in various contexts, such as applicants, employers, and organizations.
  # This class is embedded in the addressable entity, which can be of different types.
  # This class is a polymorphic association, meaning it can be associated with different models.
  #
  # @example Create a new address
  #  applicant.addresses.build(
  #    kind: 'home',
  #    address_1: '123 Main St',
  #    address_2: 'Apt 4B',
  #    city: 'Fairfield',
  #    state: 'ME',
  #    zip: '04937',
  #    county: 'Somerset',
  #    country_name: 'USA'
  #  )
  class Address
    include Mongoid::Document
    include Mongoid::Timestamps

    embedded_in :addressable, polymorphic: true

    field :kind, type: String
    field :address_1, type: String, default: ''
    field :address_2, type: String, default: ''
    field :address_3, type: String, default: ''
    field :city, type: String
    field :county, type: String, default: ''
    field :state, type: String
    field :zip, type: String
    field :country_name, type: String, default: ''
    field :quadrant, type: String, default: ''

    validates :zip, presence: true
    validates :kind, presence: true
    validates :state, presence: true

    KINDS = %w[home mailing work].freeze

    validates :kind,
              inclusion: { in: KINDS, message: '%{value} is not a valid address kind' },
              allow_blank: true

    validates :address_1, presence: { message: 'Please enter address_1' }
    validates :city, presence: { message: 'Please enter city' }

    validates :zip,
              allow_blank: false,
              format: {
                :with => /\A\d{5}(-\d{4})?\z/,
                :message => 'should be in the form: 12345 or 12345-1234'
              }
    validate :county_check

    # Scopes
    scope :mailing, -> { where(kind: 'mailing') }
    scope :home, -> { where(kind: 'home') }

    def county_check
      return unless EnrollRegistry.feature_enabled?(:display_county)
      return if self.state&.downcase != EnrollRegistry[:enroll_app].setting(:state_abbreviation).item.downcase

      if county.blank?
        errors.add(:county, 'not present')
      else
        county_name = county.titlecase
        formatted_zip = zip.match?(/-/) ? zip.split("-").first : zip
        errors.add(:county, 'invalid county/zip') if ::BenefitMarkets::Locations::CountyZip.where(zip: formatted_zip, county_name: county_name).blank?
      end
    end

    def full_address
      [address_1, address_2, address_3, city, state, zip].reject(&:blank?).join(', ')
    end
  end
end
