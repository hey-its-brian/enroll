# frozen_string_literal: true

module ContactProfile
  # Represents a person's contact preferences including preferred contact methods and language preferences
  #
  # @example Create a new preference
  #   preference = ContactProfile::Preference.new(
  #     contact_methods: ['email', 'text'],
  #     language_preference: 'en'
  #   )
  class Preference
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [r] contact_detail
    #   @return [ContactProfile::ContactDetail] The parent contact detail this preference belongs to
    embedded_in :contact_detail, class_name: 'ContactProfile::ContactDetail'

    # @return [Array<String>] Valid contact method options
    CONTACT_METHOD_KINDS = ['email', 'mail', 'text'].freeze

    # Validates that contact methods are within the allowed types
    validate :valid_contact_methods

    # Validates that a language preference is present
    validates_presence_of :language_preference

    # @!attribute [rw] contact_methods
    field :contact_methods, type: Array, default: []

    # @!attribute [rw] language_preference
    field :language_preference, type: String

    private

    # Validates that all contact methods are within the allowed types
    # @return [nil] This method doesn't return any value
    # @note Adds an error to the model if any contact method is invalid
    # @see CONTACT_METHOD_KINDS for the list of valid contact methods
    def valid_contact_methods
      return if contact_methods.all? { |method| CONTACT_METHOD_KINDS.include?(method) }

      errors.add(:contact_methods, 'must be one or more of the following: email, mail, text')
    end
  end
end
