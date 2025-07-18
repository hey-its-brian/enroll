# frozen_string_literal: true

module Publishers
  module IndividualMarket
    module Applications
      # Publisher for registering events for renewing individual market eligibility for families
      class RenewalPublisher
        include ::EventSource::Publisher[amqp: 'enroll.individual_market.applications.renewal']

        register_event 'create_renewal_draft'
        register_event 'submit_and_determine'
      end
    end
  end
end
