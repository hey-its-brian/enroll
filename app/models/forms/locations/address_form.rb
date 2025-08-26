# frozen_string_literal: true

module Forms
  module Locations
    # Form for managing address information
    # @attr_reader id [String] The ID of the address
    # @attr_reader kind [String] The type of address (e.g. 'home', 'work', 'mailing')
    # @attr_reader address_1 [String] The first line of the address
    # @attr_reader address_2 [String] The second line of the address
    # @attr_reader city [String] The city of the address
    class AddressForm
      include ActiveModel::Model
      include ActiveModel::Validations

      attr_accessor :id,
                    :kind,
                    :address_1,
                    :address_2,
                    :city,
                    :state,
                    :zip,
                    :county,
                    :_destroy

      validates :kind, presence: true, inclusion: { in: %w[home work mailing] }
      validates :address_1, :city, :state, :zip, presence: true, unless: :skip_validation?
      validates :zip, format: { with: /\A\d{5}\z/, message: "should be 5 digits" }, unless: :skip_validation?
      validates :state, inclusion: { in: State::STATE_IDS }, unless: :skip_validation?

      def initialize(attributes = {})
        super
        @kind = attributes[:kind] || 'home'
      end

      def skip_validation?
        id.present? && _destroy == "true"
      end

      def to_h
        {
          id: id,
          kind: kind,
          address_1: address_1,
          address_2: address_2,
          city: city,
          state: state,
          zip: zip,
          county: county,
          _destroy: _destroy
        }.compact
      end

      def persisted?
        id.present?
      end
    end
  end
end