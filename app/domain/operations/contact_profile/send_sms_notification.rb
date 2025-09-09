# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module ContactProfile
    # Send an SMS notification.
    class SendSmsNotification
      include Dry::Monads[:do, :result, :try]
      include EventSource::Command

      def call(params = {})
        return Success(:ok) unless EnrollRegistry.feature_enabled?(:enroll_sms_notifications)
        message_properties = yield validate(params)
        send_message(message_properties)
      end

      protected

      def validate(params)
        p_number = params[:phone_number]
        return Failure(:no_phone_number) unless p_number
        message = params[:message]
        return Failure(:no_message) unless message

        normalize_result = Try do
          normalized_phone = ::ContactProfile::Phone.normalize_phone_number(p_number)
          {
            :phone_number => normalized_phone,
            :message => message
          }
        end

        normalize_result.or(Failure(:invalid_phone_number))
      end

      def send_message(message_properties)
        event = event("events.sms_message.transmit", attributes: {phone: message_properties[:phone_number], message: message_properties[:message]})

        event.success? ? Success(event.success.publish) : event
      end
    end
  end
end