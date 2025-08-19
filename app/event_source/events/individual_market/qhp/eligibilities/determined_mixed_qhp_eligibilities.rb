# frozen_string_literal: true

module Events
  module IndividualMarket
    module Qhp
      module Eligibilities
        class DeterminedMixedQhpEligibilities < EventSource::Event
          publisher_path 'publishers.individual_market.qhp.eligibilities.determination_publisher'
        end
      end
    end
  end
end
