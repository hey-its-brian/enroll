# frozen_string_literal: true

module ContactProfile
  # Represents a personal email address within the contact profile system
  class PersonalEmail
    include Mongoid::Document
    include Mongoid::Timestamps

    # @return [ContactProfile::Email] The parent email document this personal email is embedded in
    embedded_in :email, class_name: 'ContactProfile::Email'

    # @return [String] The personal email address
    field :address, type: String
  end
end
