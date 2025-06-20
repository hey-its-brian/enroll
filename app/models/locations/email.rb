# frozen_string_literal: true

module Locations
  # The Email class represents an email address associated with an entity.
  # It is used in various contexts, such as applicants, employers, and organizations.
  # This class is embedded in the emailable entity, which can be of different types.
  # This class is a polymorphic association, meaning it can be associated with different models.
  #
  # @example Create a new email
  #  applicant.emails.build(
  #    kind: 'home',
  #    address: 'test@example.com'
  #  )
  class Email
    include Mongoid::Document
    include Mongoid::Timestamps
    include Validations::Email

    embedded_in :emailable, polymorphic: true

    KINDS = %w[home work].freeze

    field :kind, type: String
    field :address, type: String, default: ''

    validates :address, :email => true, :allow_blank => false
    validates_presence_of  :kind, message: "Choose a type"
    validates_inclusion_of :kind, in: KINDS, message: "%{value} is not a valid email type"

    validates :address,
              format: {
                :with => /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i,
                :message => "should be a valid email address"
              }

    validates :address,
              presence: true

    # Copies the email to a new emailable entity.
    #
    # @param new_emailable [Object] The new emailable entity to copy the email to
    # @return [Locations::Email] A new email instance with the same attributes as the current one
    def copy_email(new_emailable)
      new_emailable.emails.build(address: address, kind: kind)
    end

    def blank?
      address.blank?
    end

    def match(another_email)
      return false if another_email.nil?
      attrs_to_match = [:kind, :address]
      attrs_to_match.all? { |attr| attribute_matches?(attr, another_email) }
    end

    def attribute_matches?(attribute, other)
      self[attribute] == other[attribute]
    end
  end
end
