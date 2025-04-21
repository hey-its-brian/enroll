# frozen_string_literal: true

module Publishers
  # Publisher will publish events for migration results
  class MigrationResultsPublisher
    include ::EventSource::Publisher[amqp: 'enroll.migration_results']

    register_event 'enqueue_result'
  end
end
