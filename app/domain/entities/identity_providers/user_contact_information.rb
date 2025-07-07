# frozen_string_literal: true

module Entities
  module IdentityProviders
    # Information about how to contact a user.
    class UserContactInformation < Dry::Struct
      transform_keys(&:to_sym)

      # The email address at which to contact the user, for the purpose of
      # communication and password resets.
      attribute :email_contact_address, Types::String.optional.meta(omittable: true)

      # The number at which a user may receive texts.
      attribute :text_contact_number, Types::String.optional.meta(omittable: true)
    end
  end
end