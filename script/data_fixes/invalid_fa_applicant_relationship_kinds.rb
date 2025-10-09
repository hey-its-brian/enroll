# frozen_string_literal: true

# This script triggers the operation to generate report or fix invalid Financial Assistance applicant relationship kinds.
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/data_fixes/invalid_applicant_relationship_kinds.rb 'report'
#   CLIENT=me bundle exec rails runner script/data_fixes/invalid_applicant_relationship_kinds.rb 'data_fix'

p '********** STARTING - Script to renew individual market eligibility determinations for all families. **********'

if ['data_fix', 'report'].exclude?(ARGV[0])
  puts "Invalid argument: #{ARGV[0]}. Please provide either 'data_fix' or 'report'."
  puts "report - to generate a report of invalid applicant relationships."
  puts "data_fix - to fix invalid applicant relationships."
  puts 'Exiting script...'
  exit
end

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  result = ::Operations::DataFixes::CorrectInvalidFaApplicantRelationshipKinds.new.call({ action_type: ARGV[0] })

  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to renew individual market eligibility determinations for all families. **********"
