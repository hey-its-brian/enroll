# frozen_string_literal: true

module Operations
  module FinancialAssistance
    # This class will remove invalid application relationships
    # by checking if the applicant_id or relationship_id is nil
    # and then deleting those relationships
    # It will also generate a CSV report of the deleted relationships
    class DeleteInvalidApplicationRelationships
      include Dry::Monads[:do, :result]

      def call(params)
        valid_params                  = yield validate(params)
        app_ids                       = yield fetch_apps_with_invalid_relationships
        csv_report                    = yield generate_report_and_delete_relationships(app_ids, valid_params[:mode])

        Success(csv_report)
      end

      private

      def validate(params)
        return Failure("Invalid mode") unless %w[report update].include?(params[:mode])
        Success(params)
      end

      def fetch_apps_with_invalid_relationships
        # using $match to avoid applications with nil relationships
        apps_with_invalid_relationships = ::FinancialAssistance::Application.where(
          "$or" => [
            { "relationships" => { "$elemMatch" => { "applicant_id" => nil } } },
            { "relationships" => { "$elemMatch" => { "relative_id" => nil } } }
          ]
        ).pluck(:_id)

        return Failure("No invalid applications found") unless apps_with_invalid_relationships.present?
        Success(apps_with_invalid_relationships)
      rescue StandardError => e
        Failure("Error fetching applications with invalid relationships: #{e.message}")
      end

      def generate_report_and_delete_relationships(app_ids, mode)
        invalid_applications = ::FinancialAssistance::Application.where(:_id.in => app_ids).no_timeout

        date = Time.now.strftime('%Y_%m_%d')
        csv_file_name = "#{Rails.root}/deleted_application_relationships_report_#{date}.csv"

        CSV.open(csv_file_name, 'w', force_quotes: true) do |csv|
          csv << ['Application HBX ID', 'Primary HBX ID', 'AASM State', 'Created At', 'Relationships Before Deletion', 'Relationships After Deletion']
          invalid_applications.each do |app|
            app_info = extract_app_data_for_csv(app)

            delete_relationships(app) if mode == 'update'

            app_info << (mode == 'update' ? relationships_info(app) : 'No relationships deleted')
            csv << app_info
          rescue StandardError => e
            puts "Error deleting relationships for application #{app.hbx_id}: #{e.message}"
            next
          end
        end

        Success(csv_file_name)
      rescue StandardError => e
        Failure("Failed to generate report: #{e.message}")
      end

      def extract_app_data_for_csv(app)
        [
          app&.hbx_id&.to_s,
          app&.primary_applicant&.person_hbx_id&.to_s,
          app&.aasm_state,
          app&.created_at&.strftime('%Y-%m-%d %H:%M:%S'),
          relationships_info(app)
        ]
      end

      def relationships_info(application)
        application&.relationships&.map { |rel| "#{rel&.applicant_id} - #{rel&.relative_id} - #{rel&.kind}" }&.join(', ')
      end

      def delete_relationships(application)
        # replace invalid relationships with valid ones and save
        # this will overwrite the invalid relationships
        valid_relationships = application.relationships.select { |rel| rel&.valid? }
        application.relationships = valid_relationships
        application.save!

        Success("Invalid relationships deleted successfully")
      end
    end
  end
end
