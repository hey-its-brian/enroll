# frozen_string_literal: true

module Publishers
  # Notify of new inbox notification publisher.
  class SmsPublisher
    include ::EventSource::Publisher[arn: 'enroll.sms_message']

    register_event 'transmit'
  end
end
