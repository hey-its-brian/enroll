# frozen_string_literal: true

#
# This script processes applications from a CSV file and resets their relationships.
# These relationships are being reset due to the presence of conflicting or excess relationships
# which were created as the result of a bug in Family Relationships page UI.
#
# Command to trigger the script:
# bundle exec rails runner script/reset_application_relationships_from_csv.rb <path_to_csv_file>

csv_path = 'applications_with_conflicting_or_excess_relationships.csv'
result = Operations::FinancialAssistance::ResetApplicationRelationshipsFromCSV.new.call(csv_path: csv_path)

if result.success?
  puts "Application Relationships reset completed successfully!"
else
  puts "Error: #{result.failure}"
end