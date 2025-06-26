# frozen_string_literal: true

module Events
  # Indicates a new inbox message has been received
  class PersonInboxMessageReceived < EventSource::Event
    publisher_path 'publishers.people_publisher'
  end
end