# frozen_string_literal: true

# Script: Redetermine RRV-eligible families unconditionally
#
# Initiates an asynchronous migration to redetermine eligibility for families with
# outstanding verifications (OV) for a given assistance year. Families are processed
# in configurable batches and the operation’s duration is benchmarked.
#
# Usage:
#   CLIENT=me bundle exec rails runner script/families/redetermine_rrv_eligible_families_determination.rb
#   CLIENT=me bundle exec rails runner script/families/redetermine_rrv_eligible_families_determination.rb 3000 'Array' 2026
#
# Arguments (ARGV):
# @param [Integer] ARGV[0] batch_size Optional. Number of records processed per batch. Defaults to 3000.
# @param [String, nil] ARGV[1] data_type Optional. Data typing hint for the data source (e.g., 'Array').
# @param [Integer] ARGV[2] assistance_year Required. Assistance year to target for eligibility redetermination.
#
# Internals:
# @see Operations::AsyncMigrations::InitiateMigration
#   Executes an async migration given a data source and migration handler mapping.
# @see Caches::BenchmarkCache
#   Measures total execution time and returns elapsed seconds.
#
# Migration Parameters:
# @option params [String] :data_source Source for fetching candidate family IDs (e.g., 'fetch_rrv_eligible_family_ids').
# @option params [String] :migration_handler_name Handler mapping key (e.g., 'redetermine_family_eligibility_unconditionally').
# @option params [Integer] :batch_size Batch size for processing families.
# @option params [Hash] :additional_params Additional options, including:
#   @option additional_params [Integer] :assistance_year Target assistance year.
#   @option additional_params [String, nil] :data_type Data typing hint passed-through to the data source.
#
# Output:
# - Logs success or failure returned by InitiateMigration.
# - Logs total elapsed time in seconds.
#
# @return [void]
p '********** STARTING - Script to redetermine family eligibility unconditionally **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  batch_size = ARGV[0].present? ? ARGV[0].to_i : 3000
  data_type = ARGV[1].present? ? ARGV[1].to_s : nil
  assistance_year = ARGV[2].to_i

  params = {
    data_source: 'fetch_rrv_eligible_family_ids',
    migration_handler_name: 'redetermine_family_eligibility_unconditionally',
    batch_size: batch_size,
    additional_params: { assistance_year: assistance_year, data_type: data_type }
  }

  result = ::Operations::AsyncMigrations::InitiateMigration.new.call(params)

  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

# Logs the total execution time of the script
p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to redetermine family eligibility unconditionally. **********"