# frozen_string_literal: true

module Events
  module BatchProcess
    # Registers event for processing a migration batch
    class ProcessMigrationEventBatches < EventSource::Event
      publisher_path "publishers.batch_process_publisher"
    end
  end
end
