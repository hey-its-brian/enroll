# frozen_string_literal: true

module Publishers
  module IndividualMarket
    module Qhp
      module Eligibilities
        # Publisher for triggering notices when individual market applications are determined
        class DeterminationPublisher
          include ::EventSource::Publisher[amqp: 'enroll.individual_market.qhp.eligibilities']

          register_event 'determined_qhp_eligible'
          register_event 'determined_qhp_ineligible'
          register_event 'determined_mixed_qhp_eligibilities'
        end
      end
    end
  end
end
