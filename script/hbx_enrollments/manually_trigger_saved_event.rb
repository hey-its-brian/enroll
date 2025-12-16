# frozen_string_literal: true

#
# Script: Trigger "enrollment saved" events for recent enrollments and export results
#
# Overview:
# - Filters enrollments by state, creation date, and generation_reason.
# - Invokes HbxEnrollment#generate_enrollment_saved_event for each matching enrollment.
# - Writes a CSV report with success or error per enrollment.
#
# Usage:
#  bundle exec rails runner script/hbx_enrollments/manually_trigger_saved_event.rb "2025-12-08"
#
# Filters:
# - FILTERED_GENERATION_REASONS: Limits to specific generation reasons.
# - created_at: Lower bound date for enrollments processed.
#
# Input:
# - Database: HbxEnrollment documents
#   - aasm_state  HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES
#   - created_at ≥ created_at filter
#   - generation_reason  FILTERED_GENERATION_REASONS
#
# Output:
# - CSV file: enrollments_requiring_reconciliation_YYYYMMDD.csv
#   Columns:
#     - Hbx ID
#     - Enrollment State
#     - Generation Reason
#     - Created At
#     - Family ID
#     - Person HBX ID
#     - Status ("success" | "error: <message>")
#
# Side Effects:
# - Calls HbxEnrollment#generate_enrollment_saved_event (can publish events/notifications).
#
# Error Handling:
# - Per-enrollment rescue logs the error in CSV and stdout, then continues.
#
# @example Default run
#   # Processes enrollments created on/after 2025-12-08, matching allowed reasons and states
#   bundle exec rails runner script/hbx_enrollments/manually_trigger_saved_event.rb "2025-12-08"
#
# @see HbxEnrollment#generate_enrollment_saved_event
# @see HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES
FILTERED_GENERATION_REASONS = [
  :plan_shopping, :eligibility_creation, :renewal, :reinstatement, :relocation,
  :age_off, :date_change, :migration, :import, :unknown
].freeze

from_date = ARGV[0]&.to_date
file_name = "enrollments_requiring_reconciliation_#{Date.today.strftime("%Y-%m-%d")}.csv"

CSV.open(file_name, "w") do |csv|
  puts "Starting processing enrollments created on/after #{from_date}..."
  csv << ["Hbx ID", "Enrollment State", "Generation Reason", "Created At", "Family ID", "Person HBX ID", "Status"]

  HbxEnrollment.where(
    :aasm_state.in => HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES,
    :created_at.gte => from_date,
    :generation_reason.in => FILTERED_GENERATION_REASONS
  ).order_by(:created_at.asc).each do |en|
    puts "Processing enrollment #{en.hbx_id}"
    en.generate_enrollment_saved_event
    primary_person = en.family.primary_person
    csv << [en.hbx_id, en.aasm_state, en.generation_reason, en.created_at.strftime('%Y-%m-%d'), en.family_id, primary_person&.hbx_id, "success"]
  rescue StandardError => e
    csv << [en&.hbx_id, en&.aasm_state, en&.generation_reason, en&.created_at&.strftime('%Y-%m-%d'), en&.family_id, primary_person&.hbx_id, "error: #{e.message}"]
    puts "Error processing enrollment #{en&.hbx_id}: #{e.message}"
  end

  puts "Completed processing enrollments created on/after #{from_date}."
  puts "CSV report generated: #{file_name}"
end