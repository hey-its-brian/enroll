# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module People
    # Handle a person's Phone number being added, updated, or removed.
    class HandlePhoneChanged
      include EventSource::Command
      include Dry::Monads[:do, :result]

      # Executes other events which should occur in response to
      # a person's Phone number being altered.
      #
      # @param params [Hash] The parameters for the operation.
      # @option params [Phone] :phone The phone number that was changed.
      # @option params [Hash | nil] :changes The changes made.
      # @option params [Symbol] :action The change type: :update or :destroy
      # @return [Dry::Monads::Result] The result of the operation.
      def call(params = {})
        _person = yield validate(params)
        notify_of_user_contact_info_update(params[:phone])
        Success(:ok)
      end

      protected

      def notify_of_user_contact_info_update(phone)
        person = phone.person
        return Success(:ok) unless person.user
        user = person.user

        email = person.work_email_or_best
        phone = person.mobile_phone
        user_id = user.oim_id

        user_info_hash = {
          login: user_id
        }

        if email || phone
          contact_hash = {}
          contact_hash[:email_contact_address] = email if email
          contact_hash[:text_contact_number] = Phonelib.parse(phone.to_s).sanitized if phone
          user_info_hash[:contact_information] = contact_hash
        end
        user_info = Entities::IdentityProviders::UserInformation.new(user_info_hash)

        event("events.user_account_information.contact_numbers_updated", attributes: user_info.as_json).success.publish

        Success(:ok)
      end

      def validate(params)
        return Failure(:no_phone_provided) unless params[:phone].is_a?(::Phone)
        return Failure(:not_a_person_phone) unless params[:phone].person

        Success(:ok)
      end
    end
  end
end