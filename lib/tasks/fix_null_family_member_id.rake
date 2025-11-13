# frozen_string_literal: true

# Fix applications with nil family_member_id applicants (CRM 28003)
#
# Applications in determined state with applicants having nil family_member_id should be cancelled.
# This task identifies and cancels such applications by transitioning them to cancelled state.
#
# Usage:
#   # Generate impact report first
#   `bundle exec rake fix_null_family_member_id:generate_impact_list`
#
#   # Fix the data (cancel applications with nil family_member_id applicants)
#   `bundle exec rake fix_null_family_member_id:fix[CRM_NUMBER]`
#
#   # Example:
#   `bundle exec rake fix_null_family_member_id:fix[28003]`
#
# Output: CSV files saved to Rails.root as null_family_member_id_impact_YYYY_MM_DD.csv

require 'csv'

namespace :fix_null_family_member_id do
  desc "Generate impact list for applications with nil family_member_id applicants"
  task generate_impact_list: :environment do
    puts "Generating impact list for applications with nil family_member_id applicants..."

    applications = IndividualMarket::Application.where(current_state: :determined).where("applicants.family_member_id" => nil)

    puts "Found #{applications.count} applications with nil family_member_id applicants"

    if applications.any?
      puts "\nHBX IDs of primary applicants:"
      hbx_ids = applications.map { |app| app.family.primary_applicant.hbx_id }
      hbx_ids.each_with_index do |hbx_id, index|
        puts "#{index + 1}. #{hbx_id}"
      end

      # Generate CSV report
      file_name = "#{Rails.root}/null_family_member_id_impact_#{Date.today.strftime('%Y_%m_%d')}.csv"

      csv_content = CSV.generate(force_quotes: true) do |csv|
        csv << ['Application ID', 'Primary Applicant HBX ID', 'Family ID', 'Current State', 'Created At']

        applications.each do |app|
          csv << [
            app.id.to_s,
            app.family.primary_applicant.hbx_id,
            app.family.id.to_s,
            app.current_state,
            app.created_at
          ]
        end
      end

      File.write(file_name, csv_content)
      puts "\nCSV report generated: #{file_name}"
    else
      puts "No applications found with nil family_member_id applicants"
    end

  rescue StandardError => e
    puts "Error generating impact list: #{e.message}"
    puts e.backtrace.join("\n")
  end

  desc "Cancel applications with nil family_member_id applicants"
  task :fix, [:crm_number] => :environment do |_task, args|
    crm_number = args[:crm_number]
    puts "Starting fix for applications with nil family_member_id applicants (CRM #{crm_number})..."

    applications = IndividualMarket::Application.where(current_state: :determined).where("applicants.family_member_id" => nil)

    puts "Found #{applications.count} applications to process"

    if applications.any?
      processed_count = 0
      error_count = 0

      applications.each do |application|

        application.state_histories.build(
          from_state: 'determined',
          to_state: 'cancelled',
          transition_at: DateTime.now,
          effective_on: DateTime.now.to_date,
          event: 'cancel!',
          reason: "Transitioning to cancelled state due to CRM #{crm_number}",
          comment: "Transitioning to cancelled state due to CRM #{crm_number}"
        )

        application.current_state = :cancelled
        application.save!

        processed_count += 1
        puts "✓ Processed application #{application.id} for family #{application.family.primary_applicant.hbx_id}"

      rescue StandardError => e
        error_count += 1
        puts "✗ Error processing application #{application.id}: #{e.message}"

      end

      puts "\n=== Summary ==="
      puts "Total applications found: #{applications.count}"
      puts "Successfully processed: #{processed_count}"
      puts "Errors encountered: #{error_count}"

    else
      puts "No applications found to process"
    end

  rescue StandardError => e
    puts "Error running fix: #{e.message}"
    puts e.backtrace.join("\n")
  end
end
