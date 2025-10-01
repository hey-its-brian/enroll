# Script to create SSA verification types for Person records.
# This script processes a comma-separated list of person HBX IDs and attempts to create
# SSA verification types for each person. Results are logged and exported to CSV files.
#
# The script processes persons individually and generates detailed reports including
# success/failure status and execution metrics.
#
# @example Run the script with person HBX IDs
#   CLIENT=me bundle exec rails runner script/data_fixes/create_ssa_verification_type.rb "hbx123,hbx456,hbx789"
#
# @example Run the script (will exit with error if no IDs provided)
#   CLIENT=me bundle exec rails runner script/data_fixes/create_ssa_verification_type.rb
#
# @see Operations::DataFixes::CreateSsaVerificationType
#   The operation used to create SSA verification types for persons.
#
# @see Caches::BenchmarkCache
#   Utility used to measure the execution time of the script.
#
# @return [void]
# @raise [SystemExit] If no valid HBX IDs are provided via ARGV
p '********** STARTING - Script to create SSA verification types **********'

# Generates CSV files with the collected verification type creation results.
# Large datasets are automatically split into multiple files of 500,000 records each
# to ensure manageable file sizes and system performance.
#
# @private
# @param array_collection [Array<Array>] Collection of result rows for the CSV.
#   Each row contains: [person_hbx_id, verification_type, from_status, to_status, message]
# @return [Array<String>] Array of generated CSV file names
# @raise [StandardError] If there's an error writing the files
#
# @example Generated CSV structure
#   person_hbx_id,Verification Type,From Status,To Status,Message
#   "12345","SSA Verification Type","unverified","verified","Successfully created verification type"
#   "67890","SSA Verification Type","","","Error: Person not found"
def generate_csv_file(array_collection)
  file_name = []

  array_collection.each_slice(500_000).with_index do |limited_array, index|
    FileUtils.touch("ssa verification type report_collection_#{index}.csv") unless File.exist?("ssa verification type report_collection_#{index}.csv")

    csv_content = CSV.generate(force_quotes: true) do |csv|
      csv << ["person_hbx_id", "Verification Type", "From Status", "To Status", "Message"]
      limited_array.each { |row| csv << row }
    end

    File.write("ssa verification type report_collection_#{index}.csv", csv_content)
    file_name << "ssa verification type report_collection_#{index}.csv"
  end
  file_name
end

# Measures the execution time of the SSA verification type creation process.
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
    result = ::Operations::DataFixes::CreateSsaVerificationType.new.call({person_hbx_id: person_hbx_id})

    # Outputs the result of the SSA verification type creation
    if result.success?
      # puts result.success # Logs the success message
      array_collection << [person_hbx_id, "SSA Verification Type", "unverified", "verified", "Successfully created verification type"]
    else
      puts result.failure # Logs the failure message
      array_collection << [person_hbx_id, "SSA Verification Type", "", "", result.failure]
    end
  end

  generate_csv_file(array_collection)
end

# Logs the total execution time of the script
#
# @param elapsed_time [Float] The total time taken to execute the script, in seconds.
p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to create SSA verification types. **********"