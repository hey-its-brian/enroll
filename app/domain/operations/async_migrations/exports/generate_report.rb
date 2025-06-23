# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Exports
      # @!attribute [r] queue
      #   @return [Bunny::Queue] The RabbitMQ queue instance
      #
      # @description
      #   Generates a CSV report by consuming messages from a RabbitMQ queue containing
      #   evidence data for financial assistance applications. Each message is expected
      #   to contain headers and rows for the CSV file.
      #
      # @example
      #   Operations::AsyncMigrations::Exports::GenerateReport.run
      #
      class GenerateReport < ::Operations::AsyncMigrations::Exports::BaseQueueCsvExport
        # Returns the name of the RabbitMQ queue to consume messages from
        #
        # @return [String] The queue name
        def self.result_queue_name
          "on_enroll.enroll.migration_results"
        end

        # Initiates the report generation process
        #
        # @return [void]
        def build
          run_records
        end

        private

        # Processes messages from the queue and generates the CSV report
        #
        # @private
        # @return [void]
        # @raise [StandardError] If there's an error during processing
        def run_records
          counter = 0
          messages_count = @queue.message_count
          puts "Total messages in queue: #{messages_count}"
          return if messages_count.zero?

          delivery_info, _props, payload = @queue.pop(manual_ack: true)
          parsed_payload = JSON.parse(payload, symbolize_names: true)
          headers = parsed_payload[:csv_headers]
          file_name = parsed_payload[:csv_file_name]

          array_collection = []
          while delivery_info
            counter += 1
            puts "Processing record (#{counter}/#{messages_count})"
            payload = JSON.parse(payload, symbolize_names: true)
            array_collection << payload[:csv_row]

            @queue.channel.ack(delivery_info.delivery_tag)
            delivery_info, _props, payload = @queue.pop(manual_ack: true)
          end

          file_names = generate_csv_file(array_collection, headers, file_name)
          puts "Finished processing #{counter} records. CSV files created at: #{file_names.join(', ')}"
        rescue StandardError => e
          puts "Failed to generate evidence report: #{e.message}"
          raise
        end

        # Generates a CSV file with the collected data
        #
        # @private
        # @param array_collection [Array<Array>] Collection of rows for the CSV
        # @param headers [Array<String>] Column headers for the CSV
        # @param file_name [String] Path where the CSV file will be created
        # @return [void]
        # @raise [StandardError] If there's an error writing the file
        def generate_csv_file(array_collection, headers, file_name)
          file_names = []

          array_collection.each_slice(500_000).with_index do |limited_array, index|
            FileUtils.touch("#{file_name}_collection_#{index}.csv") unless File.exist?("#{file_name}_collection_#{index}.csv")

            csv_content = CSV.generate(force_quotes: true) do |csv|
              csv << headers
              limited_array.each { |row| csv << row }
            end

            File.write("#{file_name}_collection_#{index}.csv", csv_content)
            file_names << "#{file_name}_collection_#{index}.csv"
          end
          file_names
        end
      end
    end
  end
end