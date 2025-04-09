# frozen_string_literal: true

module ContactProfile
  # Email model representing an email record that can contain work and personal email details
  #
  # @example Create a new email record
  #   email = ContactProfile::Email.new
  #   email.work_email = "example@work.com"
  #   email.personal_email = "example@personal.com"
  #
  # @note This model is embedded in ContactDetail as a collection (embeds_many)
  #   to support tracking history of multiple versions of emails over time
  #
  # @see ContactProfile::ContactDetail
  class Email
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute contact_detail
    #   @return [ContactProfile::ContactDetail] The parent contact detail that contains this email
    embedded_in :contact_detail, class_name: 'ContactProfile::ContactDetail'

    # @!attribute work_email
    #   @return [String] The work email address
    field :work_email, type: String

    # @!attribute personal_email
    #   @return [String] The personal email address
    field :personal_email, type: String

    # @!scope class
    # @return [Mongoid::Criteria] The most recent Email based on creation timestamp
    scope :newest, -> { order_by(created_at: :desc).limit(1) }
  end
end
