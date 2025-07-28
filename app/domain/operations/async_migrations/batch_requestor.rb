# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    # Class responsible for requesting batches of records for migration.
    # Each event published by this class will be handled by the BatchProcessor class, which publishes a single event for each record containing data to be migrated.
    class BatchRequestor
      include Dry::Monads[:do, :result]
      include EventSource::Command

      # Requests batches of records for migration.
      #
      # @param params [Hash] Parameters for generating the batch requests.
      # @option params [String] `:data_source` the name of the model with the data to migrate. Must be a string represantion of a parent-level Mongo Document.
      # @option params [String] `:migration_handler_name` name of the operation that handles migrating data for for a single document. Must be a string representation of a class mapped in `Operations::AsyncMigrations::Mappings::EVENT_HANDLER_MAP`.
      # @option params [Integer] `:batch_size` controls the size of the batches when publishing event triggers for the event handler class. Must be an integer.
      # @return [Dry::Monads::Result] A Success or Failure monad.
      def call(params)
        @logger = yield initialize_logger
        validated_params = yield validate(params)
        query = yield fetch_batch_query(validated_params)
        result = yield initiate_batch_requests(query, validated_params)
        Success(result)
      end

      private

      # Initializes the logger.
      #
      # @return [Dry::Monads::Result] A Success monad with the logger, or a Failure monad with an error message.
      def initialize_logger
        Success(
          Logger.new(
            "#{Rails.root}/log/async_migrations_batch_requestor_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
          )
        )
      rescue StandardError => e
        Failure("Error initializing logger: #{e.message}")
      end

      # Validates the parameters for generating the batch requests.
      #
      # @param params [Hash] Parameters for generating the batch requests.
      # @return [Dry::Monads::Result] a Success monad with the validated parameters, or a Failure monad with an error message
      def validate(params)
        return Failure("Params must be a hash") unless params.is_a?(Hash)
        return Failure("Data source must be a string") unless params[:data_source].is_a?(String)
        return Failure("Event handler name must be a string") unless params[:migration_handler_name].is_a?(String)
        return Failure("Batch size must be a number") unless params[:batch_size].is_a?(Integer)
        Success(params)
      end

      # Fetches the query for the migration.
      # The query name must be present in the `Operations::AsyncMigrations::Mappings::QUERY_MAP` namespace in order to return a valid class.
      # The query is used to query the records for migration.
      #
      # @param params [Hash] Parameters for the batch request.
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

      # Generates and publishes the events to request batches of records for migration.
      #
      # @param model_class [Class] The query containing the data targeted for migration.
      # @param params [Hash] Parameters for the batch request.
      # @return [Dry::Monads::Result] A Success monad with a success message, or a Failure monad with an error message.
      def initiate_batch_requests(query, params)
        if params.dig(:additional_params, :data_type) == "Array"
          initiates_batch_requests_for_array(query, params)
        else
          initiates_batch_requests_for_objects(query, params)
        end
      rescue StandardError => e
        Failure("Error initiating batch request with params: #{params} - #{e.message}")
      end

      def initiates_batch_requests_for_objects(query, params)
        batch_size = params[:batch_size]
        total_records_count = records_to_process(query, params).count
        processed_records_count = 0

        while processed_records_count < total_records_count
          @logger.info "Requesting migration batch of size: #{batch_size}, processed records count: #{processed_records_count} of #{total_records_count}" unless Rails.env.test?
          event = build_event(processed_records_count, params)

          if event.success?
            event.success.publish
            @logger.info "Published event for params #{params} - #{event.success.inspect}" unless Rails.env.test?
          else
            @logger.error "Failed to build event for params #{params} - #{event.failure}" unless Rails.env.test?
          end

          processed_records_count += batch_size
        end
        Success("Requested migration batches with params: #{params}")
      end

      def initiates_batch_requests_for_array(query, params)
        batch_size = params[:batch_size]
        records = records_to_process(query, params)
        total_records_count = records.count
        sorted_records = records.sort if params.dig(:additional_params, :data_type) == "Array"
        processed_records_count = 0
        messages = []

        while processed_records_count < total_records_count
          @logger.info "Requesting migration batch of size: #{batch_size}, processed records count: #{processed_records_count} of #{total_records_count}" unless Rails.env.test?
          params.merge!(records: sorted_records.drop(processed_records_count).take(batch_size)) if params.dig(:additional_params, :data_type) == "Array"
          event = build_event(processed_records_count, params)

          if event.success?
            event.success.publish
            @logger.info "Published event for params #{params} - #{event.success.inspect}" unless Rails.env.test?
          else
            @logger.error "Failed to build event for params #{params} - #{event.failure}" unless Rails.env.test?
          end

          messages << "------------------------------------------------------ \n Requested migration batches with params: #{params}"
          processed_records_count += batch_size
        end
        Success(messages)
      end

      def records_to_process(query, params)
        return query if query.respond_to?(:collection)

        query.call(params)
      end

      # Builds an event for requesting a migration batch.
      #
      # @param processed_records_count [Integer] The number of records already processed.
      # @param params [Hash] Parameters for the batch request.
      # @return [Dry::Monads::Result] A Success monad with the built event, or a Failure monad with an error message.
      def build_event(processed_records_count, params)
        event(
          "events.batch_process.process_migration_event_batches",
          attributes: params.merge(skip: processed_records_count)
        )
      end
    end
  end
end
