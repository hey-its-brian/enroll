# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module ConsumerRoles
    # This operation is responsible for creating or updating contact preferences for a consumer role.
    class CreateContactPreferences
      include Dry::Monads[:do, :result]

      def call(params)
        consumer_role, attributes = yield validate_params(params)
        update_contact_preferences(consumer_role, attributes)
      end

      def validate_params(params)
        consumer_role = params[:consumer_role]
        attributes = params[:params]
        return Failure(:invalid_params) unless consumer_role.present? && attributes.present?

        Success([consumer_role, attributes])
      end

      def update_contact_preferences(consumer_role, attributes)
        consumer_role.skip_consumer_role_callbacks = true

        person = consumer_role.person
        person.assign_attributes(attributes)
        if person.save(context: :enhanced_contact_preferences)
          Success(nil)
        else
          Failure(person.errors)
        end
      end
    end
  end
end