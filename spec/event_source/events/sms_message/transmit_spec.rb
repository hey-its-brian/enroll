# frozen_string_literal: true

require 'rails_helper'
require 'event_source/rspec/event_routing_matchers'

RSpec.describe Events::SmsMessage::Transmit do
  include EventSource::Command

  it "routes correctly" do
    published_event = event("events.sms_message.transmit", attributes: {})
    expect(published_event).to route_to_publisher(:amqp, "contact_events.sms_message.transmit")
  end

end
