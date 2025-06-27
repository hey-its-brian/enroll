# frozen_string_literal: true

module Events
  module Enroll
    module Verifications
      module SsaVlp
        # This class will register event
        class Requested < EventSource::Event
          publisher_path 'publishers.verifications.ssa_vlp_publisher'

        end
      end
    end
  end
end