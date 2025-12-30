# frozen_string_literal: true

# This script triggers the operation to generate report or fix invalid applicant relationship kinds.
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/data_fixes/invalid_applicant_relationship_kinds.rb 'report' ['both'|'individual_market'|'financial_assistance']
#   CLIENT=me bundle exec rails runner script/data_fixes/invalid_applicant_relationship_kinds.rb 'data_fix' ['both'|'individual_market'|'financial_assistance']
#
# Examples:
#   CLIENT=me bundle exec rails runner script/data_fixes/invalid_applicant_relationship_kinds.rb 'report'
#   CLIENT=me bundle exec rails runner script/data_fixes/invalid_applicant_relationship_kinds.rb 'report' 'individual_market'
#   CLIENT=me bundle exec rails runner script/data_fixes/invalid_applicant_relationship_kinds.rb 'data_fix' 'financial_assistance'

p '********** STARTING - Script to correct invalid applicant relationship kinds. **********'

if ['data_fix', 'report'].exclude?(ARGV[0])
  puts "Invalid argument: #{ARGV[0]}. Please provide either 'data_fix' or 'report'."
  puts "report - to generate a report of invalid applicant relationships."
  puts "data_fix - to fix invalid applicant relationships."
  puts 'Exiting script...'
  exit
end

# Optional second argument for type (defaults to 'both')
type = ARGV[1] || 'both'
valid_types = %w[individual_market financial_assistance both]

unless valid_types.include?(type)
  puts "Invalid type argument: #{type}. Please provide 'individual_market', 'financial_assistance', or 'both'."
  puts "individual_market - to process only IndividualMarket::Application records."
  puts "financial_assistance - to process only FinancialAssistance::Application records."
  puts "both - to process both types (default)."
  puts 'Exiting script...'
  exit
end

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  result = ::Operations::DataFixes::CorrectInvalidApplicantRelationshipKinds.new.call({ action_type: ARGV[0], type: type })

  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to correct invalid applicant relationship kinds. **********"

