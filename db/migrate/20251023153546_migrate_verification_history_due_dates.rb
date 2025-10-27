# frozen_string_literal: true

# @class MigrateVerificationHistoryDueDates
# This migration updates verification history records for determined applications
# from 2026 to set the `due_on` field based on the associated evidence's `due_on` value.
# It processes both IndividualMarket and FinancialAssistance applications.
#
# @note This migration processes applications in batches to optimize memory usage
#   and provides progress logging for monitoring large datasets.
#
# @example Running the migration
#   RAILS_ENV=production bundle exec rails db:migrate:up VERSION="20251023153546"
#
# @see Mongoid::Migration
class MigrateVerificationHistoryDueDates < Mongoid::Migration

  def self.up
    if EnrollRegistry.feature_enabled?(:qhp_application)
      puts "Starting migration of verification history due dates for 2026 applications..."

      # Fetch IndividualMarket applications
      puts "Fetching IndividualMarket applications..."
      im_apps = IndividualMarket::Application.where(current_state: :determined).from_year(2026)

      # Fetch FinancialAssistance applications
      puts "Fetching FinancialAssistance applications..."
      fa_apps = FinancialAssistance::Application.determined.by_year(2026)

      migrate_apps(im_apps, "IndividualMarket")
      migrate_apps(fa_apps, "FinancialAssistance")

      puts "Migration completed successfully."
    else
      puts "QHP application feature is not enabled. Skipping migration."
    end
  end

  # No rollback logic is implemented for this migration.
  #
  # @return [void]
  def self.down; end

  # Migrates verification history due dates for a collection of applications.
  #
  # @param apps [Mongoid::Criteria] Collection of applications to migrate
  # @param type [String] Type of application for logging purposes
  #
  # @return [void]
  def self.migrate_apps(apps, type)
    batch_size = 1000
    total_apps = apps.count
    processed_count = 0
    error_count = 0

    puts "Processing #{total_apps} #{type} applications..."

    apps.batch_size(batch_size).each_with_index do |app, index|
      puts "Processing #{type} application #{index + 1}/#{total_apps}" if index % batch_size == 0

      begin
        app.applicants.each do |applicant|
          applicant.eligibilities.each do |eligibility|
            eligibility.evidences.each do |evidence|
              latest_verification_history = evidence.latest_verification_history
              latest_verification_history.set(due_on: evidence.due_on) if latest_verification_history.present? && evidence.due_on.present?
            end
          end
        end
        processed_count += 1
      rescue StandardError => e
        error_count += 1
        Rails.logger.error "Failed to update #{type} application #{app.hbx_id}: #{e.message}"
        puts "Error processing #{type} application #{app.hbx_id}: #{e.message}"
      end
    end

    puts "#{type} migration completed. Processed: #{processed_count}, Errors: #{error_count}"
  end
end
