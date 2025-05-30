# frozen_string_literal: true

# @class MigrateExistingOtherApplicationsToPopulateOriginReason
# This migration updates existing applications that are not transferred in or imported or renewal
# to populate the `origin` and `generation_reason` fields. It also generates a CSV
# report of the migrated applications, including their HBX IDs and states.
#
# @note The `update_all` method is used to perform bulk updates without triggering
#   callbacks, validations, or updating the `updated_at` field. However, the `updated_at`
#   field is explicitly updated in this migration.
#
# @example Running the migration
#   RAILS_ENV=production bundle exec rails db:migrate:up VERSION="20250502142334"
#
# @see Mongoid::Migration
class MigrateExistingOtherApplicationsToPopulateOriginReason < Mongoid::Migration

  def self.up
    if EnrollRegistry.feature_enabled?(:qhp_application)
      # Fetch applications that are not transferred in or imported or renewal
      puts "Fetching applications ..."
      application_hbx_ids = FinancialAssistance::Application.collection.aggregate(
        [
          { '$match' => {'$and' => [{ "transfer_id" => { '$eq' => nil }},
                                    { "predecessor_id" => { '$eq' => nil }},
                                    { "aasm_state" => { '$ne' => "imported" } }]}},
          { '$project' => { '_id' => 0, 'hbx_id' => 1} }
          ], allow_disk_use: true
      ).to_a.collect do |app|
        app['hbx_id']
      end

      applications = FinancialAssistance::Application.where(:hbx_id.in => application_hbx_ids)
      puts "Found #{application_hbx_ids.count} applications."
      # Perform a bulk update to set `origin`, `generation_reason`, and `updated_at`
      applications.update_all(
        origin: "user",
        generation_reason: "manual",
        updated_at: DateTime.now.strftime('%Y-%m-%d %H:%M:%S%z')
      )
      puts "Updated #{application_hbx_ids.count} applications."
      result = applications.pluck(:hbx_id, :aasm_state, :origin, :generation_reason)
      puts "Fetched HBX IDs and states of updated applications."
      puts "Generating CSV report..."
      file_name = generate_csv(result)
      puts "CSV report generated successfully, report saved at: #{file_name}"
    else
      puts "QHP application feature is not enabled. Skipping migration."
    end
  end

  # No rollback logic is implemented for this migration.
  #
  # @return [void]
  def self.down; end

  # Generates a CSV file containing the HBX IDs and states of the migrated applications.
  #
  # @param array_collection [Array<Array<String>>] A collection of arrays where each
  #   sub-array contains the HBX ID and state of an application.
  #
  # @return [void]
  # @raise [StandardError] If an error occurs while generating the CSV file.
  def self.generate_csv(array_collection)
    field_names = ["Application HBX ID", "Application State", "Origin", "Generation Reason"]
    file_name = "#{Rails.root}/other_migrated_applications_#{Date.today.strftime('%Y_%m_%d')}.csv"
    FileUtils.touch(file_name) unless File.exist?(file_name)
    csv_content = CSV.generate(force_quotes: true) do |csv|
      csv << field_names
      array_collection.each { |row| csv << row }
    end

    File.write(file_name, csv_content)
    file_name
  rescue StandardError => e
    puts "Error generating CSV: #{e.message}"
  end
end