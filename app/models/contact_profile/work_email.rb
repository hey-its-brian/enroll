# frozen_string_literal: true

module ContactProfile
  # Represents a work email address for a contact
  #
  # @example Create a new work email
  #   work_email = ContactProfile::WorkEmail.new(address: 'employee@company.com')
  class WorkEmail
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [r] email
    #   @return [ContactProfile::Email] The parent email document that embeds this work email
    embedded_in :email, class_name: 'ContactProfile::Email'

    # @!attribute [rw] address
    #   @return [String] The work email address
    field :address, type: String
  end
end
