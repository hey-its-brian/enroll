# frozen_string_literal: true

module Operations
  module FinancialAssistance
    # This class loads applications by HBX ID from a CSV file
    # and resets their relationships.
    class ResetApplicationRelationshipsFromCSV
      include Dry::Monads[:do, :result]

      def call(params)
        valid_path        = yield validate(params)
        app_ids           = yield extract_hbx_ids_from_csv(valid_path)
        _applications     = yield fetch_and_process_applications(app_ids)

        Success('Completed processing applications')
      end

      private

      def validate(params)
        return Failure("Missing csv_path") unless params[:csv_path].present?
        file_path = params[:csv_path]&.to_s
        sanitized_path = File.expand_path(file_path)
        return Failure("Invalid file path location") unless sanitized_path.start_with?(Rails.root.to_s)

        return Failure("CSV file not found at #{file_path}") unless File.exist?(sanitized_path)

        Success(sanitized_path)
      end

      def extract_hbx_ids_from_csv(csv_path)
        hbx_ids = []

        CSV.foreach(csv_path, headers: true) do |row|
          hbx_ids << row[0] if row[0].present?
        end

        return Failure("No HBX IDs found in CSV") unless hbx_ids.present?
        Success(hbx_ids)
      rescue StandardError => e
        Failure("Error reading CSV file: #{e.message}")
      end

      def fetch_and_process_applications(hbx_ids)
        ::FinancialAssistance::Application.where(:hbx_id.in => hbx_ids).no_timeout.each do |app|
          reset_application_relationships(app)
        end

        Success("Applications processed successfully")
      rescue StandardError => e
        Failure("Error fetching applications: #{e.message}")
      end

      def reset_application_relationships(application)
        application.relationships = []
        application.save!

        application.reload

        if application.relationships.empty?
          puts "Application with HBX ID #{application.hbx_id} relationships reset successfully"
        else
          puts "Application with HBX ID #{application.hbx_id} relationships reset failed"
        end
      rescue StandardError => e
        puts "Error processing application: #{e.message}"
      end
    end
  end
end