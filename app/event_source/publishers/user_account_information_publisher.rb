# frozen_string_literal: true

module Publishers
  # Publisher will send account information to Identity Providers
  class UserAccountInformationPublisher
    include ::EventSource::Publisher[amqp: 'users.account_information']

    register_event 'contact_numbers_updated'
  end
end