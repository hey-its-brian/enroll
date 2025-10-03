# Script to remove invalid person relationships for Person records.
# This script processes a comma-separated list of person HBX IDs and attempts to remove
# invalid embedded person_relationships (where the relative does not exist). Results
# are logged and exported to CSV files.
#
# @example Run the script with person HBX IDs
#   CLIENT=me bundle exec rails runner script/data_fixes/remove_invalid_person_relationships.rb "hbx123,hbx456,hbx789"
#
# @example Run the script (will exit with error if no IDs provided)
#   CLIENT=me bundle exec rails runner script/data_fixes/remove_invalid_person_relationships.rb
#
# @see Operations::DataFixes::RemoveInvalidPersonRelationships
#   The operation used to remove invalid person relationships for persons.
#
# @see Caches::BenchmarkCache
#   Utility used to measure the execution time of the script.

p '********** STARTING - Script to remove invalid person relationships **********'

require 'csv'
require 'fileutils'

# Generates CSV files with the collected relationship removal results.
# Large datasets are automatically split into multiple files of 500,000 records each
# to ensure manageable file sizes and system performance.
#
# @private
# @param array_collection [Array<Array>] Collection of result rows for the CSV.
#   Each row contains: [person_hbx_id, removed_count, message]
# @return [Array<String>] Array of generated CSV file names
# @raise [StandardError] If there's an error writing the files
def generate_csv_file(array_collection)
  file_name = []

  array_collection.each_slice(500_000).with_index do |limited_array, index|
    FileUtils.touch("remove_invalid_person_relationships_report_collection_#{index}.csv") unless File.exist?("remove_invalid_person_relationships_report_collection_#{index}.csv")

    csv_content = CSV.generate(force_quotes: true) do |csv|
      csv << ["person_hbx_id", "Removed Count", "Message"]
      limited_array.each { |row| csv << row }
    end

    File.write("remove_invalid_person_relationships_report_collection_#{index}.csv", csv_content)
    file_name << "remove_invalid_person_relationships_report_collection_#{index}.csv"
  end
  file_name
end

# Measures the execution time of the invalid relationship removal process.
# Processes each person HBX ID individually and collects results for reporting.
#
# @return [Float] The elapsed time in seconds for the entire operation
elapsed_time = Caches::BenchmarkCache.with_benchmark do

  list = ARGV[0].present? ? ARGV[0] : ""

  person_hbx_ids = list.split(',').map(&:strip).reject(&:empty?)

  if person_hbx_ids.empty?
    puts "Error: No valid HBX IDs provided"
    exit 1
  end

  array_collection = []
  person_hbx_ids.each do |person_hbx_id|
    result = ::Operations::DataFixes::RemoveInvalidPersonRelationships.new.call({person_hbx_id: person_hbx_id})

    if result.success?
      msg = result.success
      count = (msg.match(/Successfully removed (\d+)/) && $1) ? $1.to_i : nil
      array_collection << [person_hbx_id, count, msg]
    else
      array_collection << [person_hbx_id, "", result.failure]
    end
  end

  generate_csv_file(array_collection)
end

# Logs the total execution time of the script
#
# @param elapsed_time [Float] The total time taken to execute the script, in seconds.
p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to remove invalid person relationships. **********"



