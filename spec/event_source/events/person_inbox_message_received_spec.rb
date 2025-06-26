# frozen_string_literal: true

require 'rails_helper'
require 'event_source/rspec/event_routing_matchers'

RSpec.describe Events::PersonInboxMessageReceived do
  include EventSource::Command

  it "routes correctly" do
    published_event = event("events.person_inbox_message_received", attributes: {})
    expect(published_event).to route_to_publisher(:amqp, "enroll.people.person_inbox_message_received")
  end

end
