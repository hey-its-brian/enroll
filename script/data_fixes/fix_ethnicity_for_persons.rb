# frozen_string_literal: true

# This script triggers the operation to fix ethnicity for persons.
#
# Usage:
#   CLIENT=me bundle exec rails runner script/data_fixes/fix_ethnicity_for_persons.rb "HBX_ID_1,HBX_ID_2,HBX_ID_3"
#
# Examples:
#   Single HBX ID:
#     CLIENT=me bundle exec rails runner script/data_fixes/fix_ethnicity_for_persons.rb "123456789"
#   
#   Multiple HBX IDs (comma-separated):
#     CLIENT=me bundle exec rails runner script/data_fixes/fix_ethnicity_for_persons.rb "123456789,987654321,456789123"

def parse_hbx_ids(args)
  if args.empty?
    puts "Error: Please provide HBX ID(s)"
  end
  
  # Parse the comma-separated HBX IDs from the quoted string
  hbx_ids = args.first.split(',').map(&:strip).reject(&:empty?)
    
  if hbx_ids.empty?
    kl
    puts "Error: No valid HBX IDs provided"
    exit 1
  end

  hbx_ids
end

def process_single_hbx_id(hbx_id, operation)
  result = operation.call(person_hbx_id: hbx_id)
  result
end

# Parse command line arguments
hbx_ids = parse_hbx_ids(ARGV)

# Processing HBX IDs silently...

# Initialize the operation
operation = ::Operations::DataFixes::FixEthnicityForPerson.new

# Track results
successful_count = 0
failed_count = 0
results = []

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  hbx_ids.each do |hbx_id|
    result = process_single_hbx_id(hbx_id, operation)
    results << { hbx_id: hbx_id, result: result }
    
    if result.success?
      successful_count += 1
    else
      failed_count += 1
    end
  end
end

# Summary
puts "********** SUMMARY **********"
puts "Total HBX IDs processed: #{hbx_ids.length}"
puts "Successful: #{successful_count}"
puts "Failed: #{failed_count}"

if failed_count > 0
  puts
  puts "Failed HBX IDs:"
  results.select { |r| r[:result].failure? }.each do |failed_result|
    puts "  - #{failed_result[:hbx_id]}: #{failed_result[:result].failure}"
  end
end

puts "********** FINISHED in #{elapsed_time.ceil} seconds - Script to backfill missing consumer roles and demographics groups for family members **********"
