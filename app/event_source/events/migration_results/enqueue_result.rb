# frozen_string_literal: true

module Events
  module MigrationResults
    # This class will register event under 'migration_results_publisher'
    class EnqueueResult < EventSource::Event
      publisher_path "publishers.migration_results_publisher"
    end
  end
end
