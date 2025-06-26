# frozen_string_literal: true

module Events
  module SmsMessage
    # Event to publish a new message via SMS.
    class Transmit < EventSource::Event
      publisher_path 'publishers.sms_publisher'
    end
  end
end