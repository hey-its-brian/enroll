# frozen_string_literal: true

require 'rails_helper'
require 'event_source/rspec/event_routing_matchers'

RSpec.describe Events::UserAccountInformation::ContactNumbersUpdated do
  include EventSource::Command

  it "routes correctly" do
    published_event = event("events.user_account_information.contact_numbers_updated", attributes: {})
    expect(published_event).to route_to_publisher(:amqp, "users.account_information.contact_numbers_updated")
  end

end
