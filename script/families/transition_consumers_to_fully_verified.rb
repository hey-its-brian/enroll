# frozen_string_literal: true

# @file Script to transition consumer roles to "fully verified" state and produce a CSV report.
# @note Expects Rails environment and the operation: Operations::DataFixes::TransitionConsumerRolesToFullyVerified.
# @example Run from terminal
#   rails runner script/families/transition_consumers_to_fully_verified.rb "family_id_1,family_id_2,family_id_3"
# @see Operations::DataFixes::TransitionConsumerRolesToFullyVerified

require 'csv'
require 'logger'
require 'fileutils'

# Prints start banner and orchestrates the operation end-to-end.
#
# @return [void]
def runner
  puts '********** STARTING - Script to transition consumers to fully verified **********'

  family_ids = parse_family_ids(ARGV)
  logger = transition_consumer_roles_logger
  result_collection = []

  family_ids.each do |family_id|
    result = Operations::DataFixes::TransitionConsumerRolesToFullyVerified.new.call({ family_id: family_id, logger: logger })

    if result.success?
      result.success.each do |row|
        result_collection << row
      end
      puts "Successfully processed family id: #{family_id}"
    else
      puts "Failed to process family id: #{family_id}, error: #{result.failure}"
    end
  rescue StandardError => e
    warn "Exception while processing family id: #{family_id} - #{e.class}: #{e.message}"
    result_collection << [family_id, nil, nil, nil, 0, "Exception: #{e.message}"]

  end

  puts "result_collection size: #{result_collection.size}"
  filenames = generate_csv_file(result_collection)
  puts "Generated CSV files: #{filenames.join(', ')}"

  puts '********** COMPLETED - Script to transition consumers to fully verified **********'
end

# Parse family IDs from command-line arguments.
#
# Expected input: ARGV[0] contains a comma-separated list of family ids.
#
# @param argv [Array<String>] Raw command-line arguments
# @return [Array<String>] Sanitized list of family IDs
# @raise [ArgumentError] if no valid family IDs are provided
def parse_family_ids(argv)
  raw = argv[0]

  raise ArgumentError, 'No valid family IDs provided. Usage: rails runner script/families/transition_consumers_to_fully_verified.rb "id1,id2,..."' if raw.nil? || raw.strip.empty?

  raw.to_s.split(',').map(&:strip).reject(&:empty?)
end

# Generates one or more CSV files from collected result rows.
#
# @param array_collection [Array<Array(String,String)>]
#   Each inner array: [family_id, primary_hbx_id, person_hbx_id, consumer_role_state, unverified_enrollments_count, message]
# @return [Array<String>] Filenames generated
# @raise [StandardError] if file writing fails
def generate_csv_file(array_collection)
  filenames = []

  array_collection.each_slice(500_000).with_index do |limited_array, index|
    FileUtils.touch("transition_consumer_roles_to_fully_verified_report_collection_#{index}.csv") unless File.exist?("transition_consumer_roles_to_fully_verified_report_collection_#{index}.csv")

    csv_content = CSV.generate(force_quotes: true) do |csv|
      csv << ["family_id", "primary_hbx_id", "person_hbx_id", "consumer_role_state", "unverified_enrollments_count", "Message"]
      limited_array.each { |row| csv << row }
    end

    File.write("transition_consumer_roles_to_fully_verified_report_collection_#{index}.csv", csv_content)
    filenames << "transition_consumer_roles_to_fully_verified_report_collection_#{index}.csv"
  end
  filenames
end

# Builds a timestamped logger for the transition operation.
#
# @return [Logger] Logger instance writing to Rails.log directory
def transition_consumer_roles_logger
  log_file_path = File.join(
    Rails.root,
    'log',
    "transition_consumer_roles_to_fully_verified_#{DateTime.now.strftime('%Y_%m_%d_%H_%M_%S')}.log"
  )
  Logger.new(log_file_path)
end

runner