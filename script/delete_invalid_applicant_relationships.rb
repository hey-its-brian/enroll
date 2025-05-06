# frozen_string_literal: true

# This script deletes relationships where either the 'applicant_id' or the 'relationship_id' are nil.
# Command to trigger the script:
# Report mode: bundle exec rails runner script/delete_invalid_application_relationships.rb
# Regular mode: bundle exec rails runner script/delete_invalid_application_relationships.rb update

mode = ARGV[0] || 'report'

if mode == 'update'
  p "Running in REGULAR mode - relationships WILL be deleted"
else
  p "Running in REPORT mode - relationships will NOT be deleted"
end

result = ::Operations::FinancialAssistance::DeleteInvalidApplicationRelationships.new.call(mode: mode)

if result.success?
  p "Report generated: #{result.success}"
else
  p result.failure
end
