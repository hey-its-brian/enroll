# frozen_string_literal: true

module Entities
  module IdentityProviders
    # Information about a user and associated information - in a form
    # acceptable to an abstract identity provider.
    class UserInformation < Dry::Struct
      transform_keys(&:to_sym)

      # The login identifier of the user.
      attribute :login, Types::String.optional.meta(omittable: true)

      # Contact information for the user.
      attribute :contact_information, ::Entities::IdentityProviders::UserContactInformation.optional.meta(omittable: true)
    end
  end
end