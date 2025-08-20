# frozen_string_literal: true

module Validations
  # Validator class for contact preference fields
  class ContactPreferencesValidator < ActiveModel::Validator
    def validate(record)
      @record = record
      @consumer_role = record.consumer_role

      return unless @consumer_role.present?

      basic_contact_validation
      contact_method_validation
      text_contact_method_validation
      email_contact_method_validation
    end

    private

    # Validates that user has at least one valid contact method (phone or email)
    # Adds error if neither mobile phone nor home email is present and valid
    def basic_contact_validation
      has_phone = @record.mobile_phone&.present?
      has_email = @record.home_email&.present?

      @record.errors.add(:base, "An email or mobile phone number is required.") unless has_phone || has_email
    end

    # Validates that at least one contact method preference is selected
    # Adds error if no contact methods are chosen
    def contact_method_validation
      @record.errors.add(:base, "A contact method is required to proceed. If selecting Text, you must also choose Email or Mail.") if contact_method_options.empty?
    end

    # Validates text messaging contact method requirements
    # Ensures text is not the only contact method and mobile phone is present
    def text_contact_method_validation
      contact_method_options = self.contact_method_options
      return unless contact_method_options.include?("Text")

      other_methods = contact_method_options - ["Text"]
      @record.errors.add(:base, "Text cannot be your only contact method. If you select Text, you must also choose Email or Mail.") if other_methods.empty?

      has_mobile_phone = @record.mobile_phone&.valid?
      @record.errors.add(:base, "You must enter a mobile phone number to receive notices and updates by text.") unless has_mobile_phone
    end

    # Validates email contact method requirements
    # Ensures home email is present when email contact method is selected
    def email_contact_method_validation
      return unless contact_method_options.include?("Email")

      has_home_email = @record.home_email&.valid?
      @record.errors.add(:base, "You must enter an email address to receive notices and updates by email.") unless has_home_email
    end

    # Extracts and returns the selected contact method options
    # Maps the stored contact_method value to an array of method names
    #
    # @return [Array<String>] Array of selected contact methods (e.g., ["Email", "Text"])
    def contact_method_options
      return [] if @consumer_role.contact_method.blank?

      ConsumerRole::CONTACT_METHOD_MAPPING.invert[@consumer_role.contact_method] || []
    end
  end
end
