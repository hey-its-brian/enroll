# frozen_string_literal: true

#
# Script: Redetermine families with existing eligibility determinations
#
# Overview:
# - Initiates an asynchronous migration to unconditionally redetermine eligibility
#   for families that already have an eligibility determination on record.
# - Families are processed in configurable batches, and total duration is benchmarked.
#
# Usage:
#   bundle exec rails runner script/families/redetermine_families_with_eligibility_determination.rb 3000 'Array' '2025-12-08'
#
# Arguments (ARGV):
# @param [Integer] ARGV[0] batch_size Optional. Records processed per batch. Defaults to 3000.
# @param [String, nil] ARGV[1] data_type Optional. Hint passed to the data source (e.g., 'Array').
#
# Internals:
# @see Operations::AsyncMigrations::InitiateMigration
#   Executes an async migration given a data source and migration handler mapping.
# @see Caches::BenchmarkCache
#   Measures total execution time and returns elapsed seconds.
#
# Migration Parameters:
# @option params [String] :data_source
#   Source used to fetch candidate family IDs
#   (default: 'fetch_family_ids_with_eligibility_determination').
# @option params [String] :migration_handler_name
#   Handler mapping key (default: 'redetermine_family_eligibility_unconditionally').
# @option params [Integer] :batch_size
#   Batch size used for processing families.
# @option params [Hash] :additional_params
#   Additional options passed to the data source.
#   @option additional_params [String, nil] :data_type
#     Data typing hint (e.g., 'Array'); optional.
#
# Output:
# - Logs success or failure returned by InitiateMigration.
# - Logs total elapsed time in seconds.
#
# @example Custom batch size and data type
#   CLIENT=me bundle exec rails runner script/families/redetermine_families_with_eligibility_determination.rb 3000 'Array' '2025-12-08'
#
# @return [void]
p '********** STARTING - Script to redetermine family eligibility unconditionally **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  batch_size = ARGV[0].present? ? ARGV[0].to_i : 3000
  data_type = ARGV[1].present? ? ARGV[1].to_s : nil
  created_at = ARGV[2].present? ? ARGV[2].to_date : nil

  params = {
    data_source: 'fetch_family_ids_with_eligibility_determination',
    migration_handler_name: 'redetermine_family_eligibility_unconditionally',
    batch_size: batch_size,
    additional_params: { data_type: data_type, created_at: created_at }
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