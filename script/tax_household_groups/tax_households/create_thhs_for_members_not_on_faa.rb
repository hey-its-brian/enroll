# frozen_string_literal: true

# This script triggers the operation to create tax households and thh enrs for members who are
# dded after an FAA application is determined but before the enrollment is purchased
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/tax_household_groups/tax_households/create_for_members_not_on_faa.rb 2024

unless ARGV[0].present?
  puts 'Missing Arguments'
  exit
end

p '********** STARTING - Script to create missing thhs for members not on FAA  **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Calls the operation to create tax households and tax household enrollments for members who are missing on FAA applications
  # If the job is successful, it logs the success message and instructions.
  # If the job fails, it logs the failure message.
  #
  # @return [void]
  result = ::Operations::Migrations::TaxHouseholdGroups::TaxHouseholds::CreateThhsForMembersNotOnFaa.new.call({ :year => ARGV[0] })

  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to create missing thhs for members not on FAA **********"
