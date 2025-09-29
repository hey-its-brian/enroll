# frozen_string_literal: true

require 'rails_helper'
require 'event_source/rspec/event_routing_matchers'

RSpec.describe Subscribers::ContactEvents::SmsCommunicationSubscriber do
  it "correctly routes the 'contact_events.sms_communication.on_opted_out' message" do
    expect([:amqp, "contact_events.sms_communication", "opted_out"]).to route_to_subscription(Subscribers::ContactEvents::SmsCommunicationSubscriber, :on_opted_out)
  end

  it "correctly routes the 'contact_events.sms_communication.on_opted_in' message" do
    expect([:amqp, "contact_events.sms_communication", "opted_in"]).to route_to_subscription(Subscribers::ContactEvents::SmsCommunicationSubscriber, :on_opted_in)
  end
end