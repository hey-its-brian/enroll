# frozen_string_literal: true

module Events
  module Family
    module Assisters
      # This class will register event
      class AssisterFired < EventSource::Event
        publisher_path 'publishers.assister_updates_publisher'
      end
    end
  end
end
