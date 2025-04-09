# frozen_string_literal: true

module ContactProfile
  # Email model representing an email record that can contain work and personal email details
  #
  # @example Create a new email record
  #   email = ContactProfile::Email.new
  #   email.build_work_email(address: "example@work.com")
  #   email.build_personal_email(address: "example@personal.com")
  #
  # @note This model is embedded in ContactDetail as a collection (embeds_many)
  #   to support tracking history of multiple versions of emails over time
  #
  # @see ContactProfile::ContactDetail
  # @see ContactProfile::WorkEmail
  # @see ContactProfile::PersonalEmail
  class Email
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute contact_detail
    #   @return [ContactProfile::ContactDetail] The parent contact detail that contains this email
    embedded_in :contact_detail, class_name: 'ContactProfile::ContactDetail'

    # @!attribute work_email
    #   @return [ContactProfile::WorkEmail] The work email address information
    embeds_one :work_email, class_name: 'ContactProfile::WorkEmail'

    # @!attribute personal_email
    #   @return [ContactProfile::PersonalEmail] The personal email address information
    embeds_one :personal_email, class_name: 'ContactProfile::PersonalEmail'

    # @!scope class
    # @return [Mongoid::Criteria] The most recent Email based on creation timestamp
    scope :newest, -> { order_by(created_at: :desc).limit(1) }
  end
end
