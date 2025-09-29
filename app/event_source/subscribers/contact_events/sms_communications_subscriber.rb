# frozen_string_literal: true

module Subscribers
  module ContactEvents
    # Handle events about sms communication preferences
    class SmsCommunicationSubscriber
      include ::EventSource::Subscriber[amqp: 'contact_events.sms_communication']

      subscribe :on_opted_out do |delivery_info, _metadata, response|
        payload = JSON.parse(response, symbolize_names: true)
        result = Operations::ContactProfile::HandleSmsOptOutNotification.new.call(
          {
            phone: payload[:phone],
            logger: logger
          }
        )
        logger.error(result.failure) unless result.success?
        ack(delivery_info.delivery_tag)
      end

      subscribe :on_opted_in do |delivery_info, _metadata, response|
        payload = JSON.parse(response, symbolize_names: true)
        result = Operations::ContactProfile::HandleSmsOptInNotification.new.call(
          {
            phone: payload[:phone],
            logger: logger
          }
        )
        logger.error(result.failure) unless result.success?
        ack(delivery_info.delivery_tag)
      end
    end
  end
end