# frozen_string_literal: true

require 'rails_helper'
require 'event_source/rspec/event_routing_matchers'

RSpec.describe Subscribers::PeopleSubscriber do
  it "correctly routes the 'enroll.people.person_inbox_message_received' message" do
    expect([:amqp, "enroll.people", "person_inbox_message_received"]).to route_to_subscription(Subscribers::PeopleSubscriber, :on_person_inbox_message_received)
  end
end