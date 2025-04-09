# frozen_string_literal: true

module ContactProfile
  # Contact details for an entity in the contact center
  # Manages phone numbers, email addresses, and communication preferences
  class ContactDetail
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute contactable
    #   @return [Object] The polymorphic parent object containing this contact detail
    embedded_in :contactable, polymorphic: true

    # @!attribute phones
    #   @return [Array<ContactProfile::Phone>] Collection of phone numbers associated with this contact
    embeds_many :phones, class_name: 'ContactProfile::Phone'

    # @!attribute emails
    #   @return [Array<ContactProfile::Email>] Collection of email addresses associated with this contact
    embeds_many :emails, class_name: 'ContactProfile::Email'

    # @!attribute preferences
    #   @return [Array<ContactProfile::Preference>] Collection of communication preferences for this contact
    embeds_many :preferences, class_name: 'ContactProfile::Preference'

    # Retrieves the most recently added phone
    # @return [ContactProfile::Phone, nil] The newest phone or nil if none exists
    def phone
      return @phone if defined?(@phone)

      @phone = phones.newest.first
    end

    # Retrieves the most recently added mobile phone
    # @return [ContactProfile::Phone, nil] The newest mobile phone or nil if none exists
    def mobile_phone
      return @mobile_phone if defined?(@mobile_phone)

      @mobile_phone = phone.mobile_phone
    end

    # Retrieves the most recently added work phone
    # @return [ContactProfile::Phone, nil] The newest work phone or nil if none exists
    def work_phone
      return @work_phone if defined?(@work_phone)

      @work_phone = phone.work_phone
    end

    # Retrieves the most recently added email
    # @return [ContactProfile::Email, nil] The newest email or nil if none exists
    def email
      return @email if defined?(@email)

      @email = emails.newest.first
    end

    # Retrieves the work email address from the most recent email
    # @return [String, nil] The work email address or nil if none exists
    def work_email
      return @work_email if defined?(@work_email)

      @work_email = email.work_email
    end

    # Retrieves the personal email address from the most recent email
    # @return [String, nil] The personal email address or nil if none exists
    def personal_email
      return @personal_email if defined?(@personal_email)

      @personal_email = email.personal_email
    end

    # Retrieves the most recently added preference
    # @return [ContactProfile::Preference, nil] The newest preference or nil if none exists
    def preference
      return @preference if defined?(@preference)

      @preference = preferences.newest.first
    end

    # Retrieves the contact methods from the most recent preference
    # @return [Array<String>, nil] List of preferred contact methods or nil if no preference exists
    def contact_methods
      return @contact_methods if defined?(@contact_methods)

      @contact_methods = preference.contact_methods
    end

    # Retrieves the language preference from the most recent preference
    # @return [String, nil] The preferred language or nil if no preference exists
    def language_preference
      return @language_preference if defined?(@language_preference)

      @language_preference = preference.language_preference
    end
  end
end
