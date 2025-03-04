# frozen_string_literal: true

module Publishers
  # Publisher will send request payload to enroll
  class AssisterUpdatesPublisher
    include ::EventSource::Publisher[amqp: 'enroll.family.assisters']

    register_event 'assister_hired'
    register_event 'assister_fired'
  end
end
