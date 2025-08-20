# frozen_string_literal: true

# IVL Contact Preferences Page elements
class IvlContactPreferences
  def self.home_phone_field
    '#person_phones_attributes_0_full_phone_number'
  end

  def self.mobile_phone_field
    '#person_phones_attributes_1_full_phone_number'
  end

  def self.personal_email_field
    '#person_emails_attributes_0_address'
  end

  def self.work_email_field
    '#person_emails_attributes_1_address'
  end

  def self.email_contact_method
    '#contact_type_email'
  end

  def self.mail_contact_method
    '#contact_type_mail'
  end

  def self.text_contact_method
    '#contact_type_text'
  end

  def self.language_preference_dropdown
    '#person_consumer_role_attributes_language_preference'
  end

  def self.continue_button
    '.interaction-click-control-continue-to-next-step'
  end
end
