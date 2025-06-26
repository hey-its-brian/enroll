# frozen_string_literal: true

module ContactProfile
  # Represents a set of blocked phone numbers which should not be contacted.
  #
  # Encapsulates the behaviour of checking the blocklist as well as updating
  # it from other sources.
  class PhoneBlocklist
    # Check if a particular phone number is on the blocklist.
    #
    # @param phone_number [String] the number to check for on the list
    # @return [Boolean] if the number is blocked by the list
    def self.blocks?(phone_number)
      return true unless EnrollRegistry.feature_enabled?(:enroll_sms_notifications)
      ContactProfile::BlockedPhoneNumber.where(
        :number => phone_number
      ).any?
    end

    # Normalize a phone number for inclusion or checking against the
    # blocklist.
    def self.normalize_phone_number(phone_number)
      Phonelib.parse(phone_number).sanitized
    end
  end
end