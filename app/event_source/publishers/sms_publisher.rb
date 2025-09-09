# frozen_string_literal: true

module Publishers
  # Notify of new inbox notification publisher.
  class SmsPublisher
    include ::EventSource::Publisher[amqp: 'contact_events.sms_message']

    register_event 'transmit'
  end
end
