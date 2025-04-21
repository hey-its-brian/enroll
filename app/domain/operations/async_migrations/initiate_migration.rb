# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    # Class responsible for initiating an asynchronous data migration.
    # This class uses the EventSource::Command module to publish an event to trigger the migration process.
    # The event is published to the "events.batch_process.request_migration_event_batches" topic.
    # After the event is published, the BatchRequestor class will determine the number and size of batches to process and publish its own set of events for processing.
    # Each event published by the BatchRequestor class will be handled by the BatchProcessor class, which publishes a single event for each record to be migrated.
    # The operation used to migrate the data for each record is determined by the `migration_handler_name` parameter.
    class InitiateMigration
      include Dry::Monads[:do, :result]
      include EventSource::Command

      # Initiates a migration.
      #
      # @param params [Hash] Parameters for the migration.
      # @option params [String] `:data_source` the name of the model with the data to migrate. Must be a string represantion of a parent-level Mongo Document.
      # @option params [String] `:migration_handler_name` name of the operation that handles migrating data for for a single document. Must be a string representation of a class mapped in `Operations::AsyncMigrations::Mappings::EVENT_HANDLER_MAP`.
      # @option params [Integer] `:batch_size` controls the size of the batches when publishing event triggers for the event handler class. Must be an integer.
      # @return [Dry::Monads::Result] A Success or Failure monad.
      def call(params)
        validated_params = yield validate(params)
        event = yield build_event(validated_params)
        result = yield initiate_migration(event)
        Success(result)
      end

      private

      # Validates the parameters for the migration.
      #
      # @param params [Hash] parameters for the migration
      # @return [Dry::Monads::Result] A Success monad with the validated parameters, or a Failure monad with an error message.
      def validate(params)
        return Failure("Params must be a hash") unless params.is_a?(Hash)
        return Failure("Data source must be a string") unless params[:data_source].is_a?(String)
        return Failure("Event handler name must be a string") unless params[:migration_handler_name].is_a?(String)
        return Failure("Batch size must be a number") unless params[:batch_size].is_a?(Integer)
        Success(params)
      end

      # Builds an event to trigger the migration process.
      #
      # @param params [Hash] parameters for the migration
      # @return [Dry::Monads::Result] A Success monad with the built event ready to publish, or a Failure monad with an error message.
      def build_event(params)
        data_source = params[:data_source]
        migration_handler_name = params[:migration_handler_name]
        batch_size = params[:batch_size]
        event(
          "events.batch_process.request_migration_event_batches",
          attributes: {
            data_source: data_source,
            migration_handler_name: migration_handler_name,
            batch_size: batch_size,
            additional_params: params[:additional_params]
          }
        )
      end

      # Initiates the migration by publishing the event.
      #
      # @param event [EventSource::Event] The event to publish.
      # @return [Dry::Monads::Result] A Success monad with a success message, or a Failure monad with an error message.
      def initiate_migration(event)
        return Failure("Failed to publish event to initiate migration") unless event.publish
        Success("Successfully published event to initiate migration")
      end
    end
  end
end
