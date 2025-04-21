# frozen_string_literal: true

# This script triggers the operation to redetermine family eligibility for all the families with outstanding verifications.
#
# Command to trigger the script:
#   CLIENT=me bundle exec rails runner script/families/redetermine_family_eligibility.rb [assistance_year] [date_threshold]
#
# Example:
#   CLIENT=me bundle exec rails runner script/families/redetermine_family_eligibility.rb 2025 2025-12-31
#
# If no arguments provided, defaults to:
#   assistance_year: current year
#   date_threshold: beginning of today

p '********** STARTING - Script to determine family eligibility for families with OV **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Parse command line arguments
  assistance_year = ARGV[0] ? ARGV[0].to_i : TimeKeeper.date_of_record.year
  date_threshold = ARGV[1] ? Date.parse(ARGV[1]).beginning_of_day : TimeKeeper.date_of_record.beginning_of_day

  # Log the parameters being used
  puts "Using assistance_year: #{assistance_year}"
  puts "Using date_threshold: #{date_threshold}"

  # Calls the operation to redetermine family eligibility for all the families with outstanding verifications.
  params = {
    data_source: 'families_with_id',
    migration_handler_name: '::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility',
    batch_size: 3000,
    additional_params: { assistance_year: assistance_year, date_threshold: date_threshold }
  }

  result = ::Operations::AsyncMigrations::InitiateMigration.new.call(params)

  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to determine family eligibility for families with OV. **********"
