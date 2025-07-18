# frozen_string_literal: true

module Events
  module IndividualMarket
    module Applications
      module Renewal
        # Includes publisher path for registering the event to create a renewal draft
        class CreateRenewalDraft < ::EventSource::Event
          publisher_path 'publishers.individual_market.applications.renewal_publisher'
        end
      end
    end
  end
end
