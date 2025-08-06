# frozen_string_literal: true

module Events
  module Enroll
    module Verifications
      module SsaVlp
        module CloseCase
          # This class will register event
          class Requested < EventSource::Event
            publisher_path 'publishers.verifications.close_case_publisher'

          end
        end
      end
    end
  end
end