# frozen_string_literal: true

module Validations
  module ContactPreferences
    # Validator class for contact preference fields
    class Validator < ActiveModel::Validator
      def validate(record)
        @record = record
        @adapter = adapter_for(record)

        basic_contact_validation
        contact_method_validation
        text_contact_method_validation
        email_contact_method_validation
      end

      private

      def adapter_for(record)
        case record
        when Person
          Validations::ContactPreferences::Adapters::PersonContactPreferencesAdapter.new(record)
        when FinancialAssistance::Applicant
          Validations::ContactPreferences::Adapters::FinancialAssistanceApplicantContactPreferencesAdapter.new(record)
        when IndividualMarket::Applicant
          Validations::ContactPreferences::Adapters::ApplicantContactPreferencesAdapter.new(record)
        else
          raise "Unknown record type: #{record.class}"
        end
      end

      # Helper method to check if mobile phone is present and valid
      def has_phone?
        @adapter.mobile_phone&.valid?
      end

      # Helper method to check if home email is present and valid
      def has_email?
        @adapter.home_email&.valid?
      end

      # Validates that user has at least one valid contact method (phone or email)
      # Adds error if neither mobile phone nor home email is present and valid
      def basic_contact_validation
        @record.errors.add(:base, "An email or mobile phone number is required.") unless has_phone? || has_email?
      end

      # Validates that at least one contact method preference is selected
      # Adds error if no contact methods are chosen
      def contact_method_validation
        @record.errors.add(:base, "A contact method is required to proceed. If selecting Text, you must also choose Email or Mail.") if @adapter.contact_method_options.empty?
      end

      # Validates text messaging contact method requirements
      # Ensures text is not the only contact method and mobile phone is present
      def text_contact_method_validation
        options = @adapter.contact_method_options
        return unless options.include?("Text")

        other_methods = options - ["Text"]
        @record.errors.add(:base, "Text cannot be your only contact method. If you select Text, you must also choose Email or Mail.") if other_methods.empty?

        @record.errors.add(:base, "You must enter a mobile phone number to receive notices and updates by text.") unless has_phone?
      end

      # Validates email contact method requirements
      # Ensures home email is present when email contact method is selected
      def email_contact_method_validation
        return unless @adapter.contact_method_options.include?("Email")

        @record.errors.add(:base, "You must enter an email address to receive notices and updates by email.") unless has_email?
      end
    end
  end
end
