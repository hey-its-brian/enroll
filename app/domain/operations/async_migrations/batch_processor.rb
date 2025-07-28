# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    # Class responsible for processing a batch of records for migration.
    # This class uses the parameters passed in to determine the query and event handler to use for migrating data on a single record.
    # It also uses the parameters to determine the number of records to skip and the size of the batch to process.
    class BatchProcessor
      include Dry::Monads[:do, :result]
      include EventSource::Command

      # Processes a batch of records for migration.
      #
      # @param params [Hash] Parameters for processing the batch of records.
      # @option params [String] `:data_source` the name of the model with the data to migrate. Must be a string represantion of a parent-level Mongo Document.
      # @option params [String] `:migration_handler_name` name of the operation that handles migrating data for for a single document. Must be a string representation of a class mapped in `Operations::AsyncMigrations::Mappings::EVENT_HANDLER_MAP`.
      # @option params [Integer] `:skip` the number of records to skip when batching. Must be an integer.
      # @option params [Integer] `:batch_size` controls the size of the batch. Must be an integer.
      # @return [Dry::Monads::Result] A Success or Failure monad.
      def call(params)
        @logger = yield initialize_logger
        validated_params = yield validate(params)
        query = yield fetch_batch_query(validated_params)
        result = yield process_migration_batch(query, validated_params)
        Success(result)
      end

      private

      # Initializes the logger.
      #
      # @return [Dry::Monads::Result] A Success monad with the logger, or a Failure monad with an error message.
      def initialize_logger
        Success(
          Logger.new(
            "#{Rails.root}/log/async_migrations_batch_processor_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
          )
        )
      rescue StandardError => e
        Failure("Error initializing logger: #{e.message}")
      end

      # Validates the parameters for the batch processing.
      #
      # @param params [Hash] Parameters for the batch processing.
      # @return [Dry::Monads::Result] a Success monad with the validated parameters, or a Failure monad with an error message.
      def validate(params)
        return Failure("Params must be a hash") unless params.is_a?(Hash)
        return Failure("Data source must be a string") unless params[:data_source].is_a?(String)
        return Failure("Event handler name must be a string") unless params[:migration_handler_name].is_a?(String)
        return Failure("Skip must be a number") unless params[:skip].is_a?(Integer)
        return Failure("Batch size must be a number") unless params[:batch_size].is_a?(Integer)

        Success(params)
      end

      # Fetches the query for the migration.
      # The query name must be present in the `Operations::AsyncMigrations::Mappings::QUERY_MAP` namespace in order to return a valid class.
      # The query is used to query the records for migration.
      #
      # @param params [Hash] Parameters for processing the batch.
      # @return [Dry::Monads::Result] A Success monad with the query, or a Failure monad with an error message.
      def fetch_batch_query(params)
        data_source = params[:data_source]
        query = ::Operations::AsyncMigrations::Mappings::QUERY_MAP[data_source]
        if query
          Success(query)
        else
          Failure("query not found for string: #{data_source}. A string-to-class mapping must be present in ::Operations::AsyncMigrations::Mappings::MODEL_MAP.")
        end
      end

      # Processes the migration batch by publishing events for each record in the batch.
      # The event will trigger the migration operation specified by the `migration_handler_name` parameter.
      #
      # @param query [Class] The query containing the data targeted for migration.
      # @param params [Hash] parameters for the batch processing
      # @return [Dry::Monads::Result] A Success monad with a success message, or a Failure monad with an error message.
      def process_migration_batch(query, params)
        if params.dig(:additional_params,:data_type) == "Array"
          process_migration_batch_for_array(params)
        else
          process_migration_for_mongo_objects(query, params)
        end
      rescue StandardError => e
        Failure("Error processing batch request with params: #{params} - #{e.message}")
      end

      def process_migration_for_mongo_objects(query, params)
        migration_handler_name = params[:migration_handler_name]
        skip = params[:skip]
        limit = params[:batch_size]
        records = records_to_process(query, params)
        records.order(:_id.asc).skip(skip).limit(limit).each do |document|
          event = build_event(migration_handler_name, document.id, params)
          if event.success?
            event.success.publish
            @logger.info "Published event for params #{params} - #{event.success}" unless Rails.env.test?
          else
            @logger.error "Failed to build event for document id #{document.id} with params #{params} - #{event.failure}" unless Rails.env.test?
          end
        end
        Success("process_migration_for_mongo_objects: Published batch of events for migration using params: #{params}")
      end

      # Processes the migration batch by publishing events for each record in the batch.
      # The event will trigger the migration operation specified by the `migration_handler_name` parameter.
      #
      # @param query [Class] The query containing the data targeted for migration.
      # @param params [Hash] parameters for the batch processing
      # @return [Dry::Monads::Result] A Success monad with a success message, or a Failure monad with an error message.
      def process_migration_batch_for_array(params)
        migration_handler_name = params[:migration_handler_name]
        records = params[:records]

        records.each do |id|
          event = build_event(migration_handler_name, id, params)
          if event.success?
            event.success.publish
            @logger.info "Published event for params #{params} - #{event.success}" unless Rails.env.test?
          else
            @logger.error "Failed to build event for document id #{id} with params #{params} - #{event.failure}" unless Rails.env.test?
          end
        end
        Success("process_migration_batch_for_array: Published batch of events for migration using params: #{params}")
      end

      def records_to_process(query, params)
        return query if query.respond_to?(:collection)

        query.call(params)
      end

      # Builds an event for triggering the migration operation for a single document.
      #
      # @param migration_handler_name [String] The name of the event handler.
      # @param document_id [String] The id of the document to process.
      # @return [Dry::Monads::Result] A Success monad with the built event, or a Failure monad with an error message.
      def build_event(migration_handler_name, document_id, params)
        event(
          "events.batch_process.process_migration_event",
          attributes: {
            migration_handler_name: migration_handler_name,
            document_id: document_id,
            additional_params: params[:additional_params]
          }
        )
      end
    end
  end
end

