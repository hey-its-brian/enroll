# frozen_string_literal: true

module Events
  module BatchProcess
    # Registers event for processing the migration of a single record
    class ProcessMigrationEvent < EventSource::Event
      publisher_path "publishers.batch_process_publisher"
    end
  end
end
