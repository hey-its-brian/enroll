# frozen_string_literal: true

require "bunny"

module Operations
  module AsyncMigrations
    module Exports
      # Base class for exporting data from message queues to CSV files
      #
      # This abstract class provides the foundation for consuming messages from
      # RabbitMQ queues and exporting the data to CSV files. It handles the connection
      # to RabbitMQ and provides hooks for subclasses to implement the specific
      # message consumption and CSV export logic.
      #
      # Subclasses must implement:
      # - self.result_queue_name: to specify which queue to consume from
      # - build: to define how to process messages and create the CSV
      #
      #   MyExporter.run
      class BaseQueueCsvExport
        # Initialize a new CSV export operation
        #
        # @param channel [Bunny::Channel] The RabbitMQ channel
        # @param queue [Bunny::Queue] The queue to consume messages from
        def initialize(channel, queue)
          @channel     = channel
          @connection  = channel.connection
          @queue       = queue
        end

        class << self
          # The name of the queue to consume messages from
          #
          # @return [String] The queue name
          # @raise [NotImplementedError] If not implemented by subclass
          def result_queue_name
            raise NotImplementedError, "#{self}.result_queue_name must be defined"
          end

          # Creates and configures the queue for consumption
          #
          # @param channel [Bunny::Channel] The RabbitMQ channel
          # @return [Bunny::Queue] The configured queue
          def create_queue(channel)
            channel.queue(result_queue_name, durable: true)
          end

          # Gets the connection proxy for the message queue
          #
          # @return [EventSource::ConnectionProxy] The connection proxy
          def connection_proxy
            EventSource::ConnectionManager
              .instance
              .find_connection(
                protocol: :amqp,
                subscribe_operation_name: result_queue_name
              )
              .connection_proxy
          end

          # Gets the connection URI from the proxy
          #
          # @return [String] The connection URI
          def connection_uri
            connection_proxy.connection_uri
          end

          # Runs the export operation
          #
          # Establishes a RabbitMQ connection, creates a channel and queue,
          # then hands off to the instance's build method to process messages
          # and create the CSV file.
          def run
            conn = Bunny.new(connection_uri, heartbeat: 15)
            conn.start

            chan  = conn.create_channel
            queue = create_queue(chan)
            new(chan, queue).build
          end
        end

        # Process messages and build the CSV file
        #
        # @abstract Must be implemented by subclasses
        def build
          raise NotImplementedError, "#{self.class}#build must be defined"
        end
      end
    end
  end
end
