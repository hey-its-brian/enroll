# frozen_string_literal: true

module Publishers
  module Verifications
    # Publisher will send request payload to SSA Hub
    class CloseCasePublisher
      include ::EventSource::Publisher[amqp: 'enroll.verifications.ssavlp.closecase']

      register_event 'requested'
    end
  end
end