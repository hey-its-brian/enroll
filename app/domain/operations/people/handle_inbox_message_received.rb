# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module People
    # Handle a new inbox message arriving for a Person.
    class HandleInboxMessageReceived
      include Dry::Monads[:do, :result]

      # Executes other events which should occur in response to a message
      # arriving in an individual's inbox.
      #
      # @param params [Hash] The parameters for the operation.
      # @option params [String] :person_id The ID of the individual who
      #                         received a new message.
      # @return [Dry::Monads::Result] The result of the operation.
      def call(params = {})
        person = yield validate(params)
        notify_using_text(person)
      end

      protected

      def notify_using_text(person)
        consumer_role = person.consumer_role

        return Success(:consumer_cant_receive_texts) unless consumer_role&.can_receive_text_communication?

        ::Operations::ContactProfile::SendSmsNotification.new.call(
          {
            phone_number: consumer_role.mobile_phone.to_s,
            message: EnrollRegistry[:enroll_sms_notifications].setting(:sms_inbox_notification_text)&.item
          }
        )
      end

      def validate(params)
        person_id = params[:person_id]
        return Failure(:invalid_person_id) unless person_id
        person = Person.where(_id: person_id).first
        return Failure(:no_such_person) unless person
        Success(person)
      end
    end
  end
end