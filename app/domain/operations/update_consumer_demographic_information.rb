# frozen_string_literal: true

module Operations
  # This operation is responsible for updating consumer demographic information based on the report: consumers_needing_updates.csv
  class UpdateConsumerDemographicInformation
    include Dry::Monads[:do, :result]

    def call(params)
      file_path          = yield validate(params)
      _disable_callbacks = yield disable_callbacks
      results            = yield build_demographic_params(file_path)
      _generate_csvs     = yield generate_csvs(results)
      _enable_callbacks  = yield enable_callbacks
      Success("Consumer demographic information updated successfully. CSV files generated.")
    end

    def validate(params)
      file_path = params[:file_path]
      return Failure("File path is missing") if file_path.blank?

      Success(file_path)
    end

    def disable_callbacks
      Person.skip_callback(:update, :after, :publish_updated_event)
      ConsumerRole.skip_callback(:update, :after, :publish_updated_event)
      LawfulPresenceDetermination.skip_callback(:update, :after, :publish_updated_event)
      Address.skip_callback(:update, :after, :notify_address_changed)
      Success("Callbacks disabled")
    end

    def enable_callbacks
      Person.set_callback(:update, :after, :publish_updated_event)
      ConsumerRole.set_callback(:update, :after, :publish_updated_event)
      LawfulPresenceDetermination.set_callback(:update, :after, :publish_updated_event)
      Address.set_callback(:update, :after, :notify_address_changed)
      Success("Callbacks enabled")
    end

    def build_demographic_params(file_path)
      date = DateTime.now.strftime("%Y_%m_%d")
      results = {}
      changed_results = {}

      report_logger = "report_logger_#{date}.csv"
      logger_headers = ['Hbx Id', 'Error']
      CSV.open(report_logger, 'w', force_quotes: true) do |logger_csv|
        logger_csv << logger_headers

        CSV.foreach(file_path, headers: true) do |row|
          hbx_id_key = row.first[0]
          hbx_id = row[hbx_id_key]
          next unless hbx_id
          process_consumer_row(row, hbx_id, results, changed_results, logger_csv)
        end
      end
      Success({results: results, changed_results: changed_results})
    end

    def process_consumer_row(row, hbx_id, results, changed_results, logger_csv)
      person = Person.where(hbx_id: hbx_id).first
      return unless person
      update_data = initialize_update_data(person)
      ::Operations::ProcessConsumerAttributes.new.call(row: row, update_data: update_data, results: results, changed_results: changed_results, hbx_id: hbx_id)
      apply_updates = ::Operations::ApplyConsumerDemographicUpdates.new.call(update_data)
      puts "Failure applying updates: #{apply_updates.failure}" if apply_updates.failure?
    rescue StandardError => e
      logger_csv << [hbx_id, e.inspect]
    end

    def initialize_update_data(person)
      {
        person: person,
        consumer_role: person.consumer_role,
        mailing_address: person.addresses.where(kind: 'mailing').first,
        home_address: person.addresses.where(kind: 'home').first,
        home_email_address: person.emails.where(kind: 'home').first,
        work_email_address: person.emails.where(kind: 'work').first,
        home_phone: person.phones.where(kind: 'home').first,
        work_phone: person.phones.where(kind: 'work').first,
        mobile_phone: person.phones.where(kind: 'mobile').first,
        person_params: {},
        mailing_address_params: {},
        destroyed_mailing_address_params: {},
        home_address_params: {},
        consumer_role_attributes: {},
        lawful_presence_determination_attributes: {},
        home_email_hash: {},
        work_email_hash: {},
        home_phone_hash: {},
        work_phone_hash: {},
        mobile_phone_hash: {},
        changes: [],
        different_values: []
      }
    end

    def generate_csvs(params)
      generate_changes_made_csv(params[:results])
      generate_different_changes_csv(params[:changed_results])

      Success("CSVs generated")
    end

    private

    def generate_changes_made_csv(results)
      date = DateTime.now.strftime("%Y_%m_%d")
      output_csv = "changes_made_#{date}.csv"

      max_diff_count = results.values.map(&:length).max || 0
      header_row = ["hbx_id"]
      (1..max_diff_count).each do |i|
        header_row << "changed#{i}_attribute" << "original#{i}_report1_value" << "changed#{i}_report2_value"
      end

      CSV.open(output_csv, "w") do |csv|
        csv << header_row
        results.each do |hbx_id, diffs|
          row = [hbx_id]
          diffs.each do |diff|
            row.concat(diff)
          end
          remaining = max_diff_count - diffs.length
          remaining.times { row.concat(["", "", ""]) }
          csv << row
        end
      end
    end

    def generate_different_changes_csv(changed_results)
      date = DateTime.now.strftime("%Y_%m_%d")
      output_csv_2 = "different_changes_#{date}.csv"

      max_diff_count = changed_results.values.map(&:length).max || 0
      header_row = ["hbx_id"]
      (1..max_diff_count).each do |i|
        header_row << "attribute#{i}" << "original_value#{i}_value" << "current#{i}_value"
      end

      CSV.open(output_csv_2, "w") do |csv_2|
        csv_2 << header_row
        changed_results.each do |hbx_id, diffs|
          row = [hbx_id]
          diffs.each do |diff|
            row.concat(diff)
          end
          csv_2 << row
        end
      end
    end
  end
end