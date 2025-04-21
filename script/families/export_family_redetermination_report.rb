# frozen_string_literal: true

# This script triggers the operation to pull csv data from the message queue and write it to a CSV file.
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/families/export_family_redetermination_report.rb
#
# Example:
#   CLIENT=me bundle exec rails runner script/families/export_family_redetermination_report.rb

p '********** STARTING - Script to pull csv data from the message queue **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
 ::Operations::AsyncMigrations::Exports::Families::Eligibility::ExportFamilyEligibilityCsv.run
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to determine family eligibility for families with OV. **********"
