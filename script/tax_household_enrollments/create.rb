# frozen_string_literal: true

# This script triggers the operation to create tax household enrollments for enrollments.
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/tax_household_enrollments/create.rb "12345,67890,11223"

enrollment_hbx_ids = ARGV[0]
if enrollment_hbx_ids.blank?
  puts "Please provide enrollment_hbx_ids as a comma-separated list."
  exit
end

p '********** STARTING - Script to create missing for tax household enrollments for enrollments  **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Calls the operation to create tax household enrollments for hbx enrollments
  # If the job is successful, it logs the success message and instructions.
  # If the job fails, it logs the failure message.
  #
  # @return [void]
  enrollment_hbx_ids = enrollment_hbx_ids.split(',').map(&:strip)
  result = Operations::Migrations::TaxHouseholdEnrollments::Create.new.call(enrollment_hbx_ids: enrollment_hbx_ids)

  if result.success?
    puts result.success
  else
    puts "Error: #{result.failure}"
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to create missing for tax household enrollments for enrollments **********"
