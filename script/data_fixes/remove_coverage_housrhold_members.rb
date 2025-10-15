# frozen_string_literal: true
# Script: Remove invalid Coverage Household Members
#
# Behavior
#   - Accepts a comma‑separated list of person HBX IDs via ARGV[0].
#   - Runs the data‑fix operation per person.
#   - Collects a status row: [person_hbx_id, message].
#   - Writes one or more CSV files:
#       remove_invalid_coverage_household_members_report_collection_<index>.csv
#     (500,000 row chunking).
#   - Emits timing metrics via Caches::BenchmarkCache.
#
# Input
#   ARGV[0]  String  Comma‑separated person HBX IDs. Required.
#
# Output
#   CSV file(s) with header:
#     person_hbx_id,Message
#
# Examples
#   CLIENT=me bundle exec rails runner \
#     script/data_fixes/remove_coverage_housrhold_members.rb "12345,67890"
#
#   (No IDs – exits with error)
#   CLIENT=me bundle exec rails runner \
#     script/data_fixes/remove_coverage_housrhold_members.rb
#
# Dependencies
#   @see Operations::DataFixes::RemoveInvalidCoverageHouseholdMember
#   @see Caches::BenchmarkCache
#
# Notes
#   - Adjust chunk size (500_000) if memory constraints arise.
#   - Operation expected to return Dry::Monads::Result.
#
# @raise [SystemExit] when no valid HBX IDs are provided.
# @return [void]
p '********** STARTING - Script to remove invalid coverage household members **********'

# Generates one or more CSV files from collected result rows.
#
# @param array_collection [Array<Array(String,String)>]
#   Each inner array: [person_hbx_id, message]
# @return [Array<String>] Filenames generated
# @raise [StandardError] if file writing fails
def generate_csv_file(array_collection)
  file_name = []

  array_collection.each_slice(500_000).with_index do |limited_array, index|
    FileUtils.touch("remove_invalid_coverage_household_members_report_collection_#{index}.csv") unless File.exist?("remove_invalid_coverage_household_members_report_collection_#{index}.csv")

    csv_content = CSV.generate(force_quotes: true) do |csv|
      csv << ["person_hbx_id", "Message"]
      limited_array.each { |row| csv << row }
    end

    File.write("remove_invalid_coverage_household_members_report_collection_#{index}.csv", csv_content)
    file_name << "remove_invalid_coverage_household_members_report_collection_#{index}.csv"
  end
  file_name
end

# Measures total execution time for processing all provided person HBX IDs.
# @return [Float] Elapsed seconds
elapsed_time = Caches::BenchmarkCache.with_benchmark do
  list = ARGV[0].present? ? ARGV[0] : ""

  person_hbx_ids = list.split(',').map(&:strip).reject(&:empty?)

  if person_hbx_ids.empty?
    puts "Error: No valid HBX IDs provided"
    exit 1
  end

  array_collection = []
  person_hbx_ids.each do |person_hbx_id|
    result = ::Operations::DataFixes::RemoveInvalidCoverageHouseholdMember.new.call({ person_hbx_id: person_hbx_id })

    if result.success?
      array_collection << [person_hbx_id, "Successfully removed invalid coverage household members"]
    else
      puts result.failure
      array_collection << [person_hbx_id, result.failure]
    end
  end

  generate_csv_file(array_collection)
end

# Log summary timing.
# @param elapsed_time [Float]
p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to remove invalid coverage household members. **********"