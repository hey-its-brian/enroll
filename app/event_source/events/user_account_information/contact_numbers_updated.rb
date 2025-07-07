# frozen_string_literal: true

module Events
  module UserAccountInformation
    # A user's contact numbers have been updated.
    class ContactNumbersUpdated < EventSource::Event
      publisher_path 'publishers.user_account_information_publisher'
    end
  end
end
