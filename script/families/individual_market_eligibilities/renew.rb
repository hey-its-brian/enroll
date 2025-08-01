# frozen_string_literal: true

# This script triggers the operation to renew individual market eligibility determinations for all the families.
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/families/individual_market_eligibilities/renew.rb

p '********** STARTING - Script to renew individual market eligibility determinations for all families. **********'

renewal_year = ARGV[0].to_i
if renewal_year < 2026
  puts "Invalid renewal year: #{renewal_year}. Please provide a year greater than or equal to 2026."
  exit
end

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Calls the operation to renew individual market eligibility determinations for all families.
  # If the job is successful, it logs the success message and instructions.
  # If the job fails, it logs the failure message.
  #
  # @return [void]
  result = ::Operations::Families::IndividualMarketEligibilities::InitiateRenewal.new.call(
    renewal_year: renewal_year
  )

  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to renew individual market eligibility determinations for all families. **********"
