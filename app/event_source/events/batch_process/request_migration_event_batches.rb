# frozen_string_literal: true

module Events
  module BatchProcess
    # Registers event for initiating batched migration
    class RequestMigrationEventBatches < EventSource::Event
      publisher_path "publishers.batch_process_publisher"
    end
  end
end
