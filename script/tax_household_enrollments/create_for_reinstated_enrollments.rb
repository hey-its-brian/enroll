# frozen_string_literal: true

# This script triggers the operation to create tax household enrollments for missing reinstated enrollments.
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/tax_household_enrollments/create_for_reinstated_enrollments.rb 2024

unless ARGV[0].present?
  puts 'Missing Arguments'
  exit
end

p '********** STARTING - Script to create missing for tax household enrollments for reinstated enrollments  **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Calls the operation to create tax household enrollments for reinstated enrollments
  # If the job is successful, it logs the success message and instructions.
  # If the job fails, it logs the failure message.
  #
  # @return [void]
  result = ::Operations::Migrations::TaxHouseholdEnrollments::CreateForReinstatedEnrollments.new.call({ :year => ARGV[0] })

  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to create missing for tax household enrollments for reinstated enrollments **********"
