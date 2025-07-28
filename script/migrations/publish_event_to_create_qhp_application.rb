# frozen_string_literal: true
# This script publishes an event to create a QHP application.
# @example Run the script
#   #   CLIENT=me bundle exec rails runner script/migrations/publish_event_to_create_qhp_application.rb
#       CLIENT=me bundle exec rails runner script/migrations/publish_event_to_create_qhp_application.rb 3000 'Array'
#
# @see Operations::AsyncMigrations::InitiateMigration
#   The operation used to initiate the migration process.
#
# @see Caches::BenchmarkCache
#   Utility used to measure the execution time of the script.
#
p '********** STARTING - Script to fetch families without determined fa applications **********'

# Measures the execution time of the migration process.
elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Parameters for reducing the records size
  batch_size = ARGV[0].present? ? ARGV[0].to_i : 3000
  data_type = ARGV[1].present? ? ARGV[1].to_s : nil

  params = {
    data_source: 'families_without_determined_fa_applications_for_current_year', # Specifies the data source for the migration
    migration_handler_name: 'create_qhp_application', # Mapping key for the migration handler
    batch_size: batch_size, # Number of records to process in each batch
    additional_params: { assistance_year: 2025, data_type: data_type } # Additional parameters for the migration
  }

  result = ::Operations::AsyncMigrations::InitiateMigration.new.call(params)

  # Outputs the result of the migration
  if result.success?
    puts result.success # Logs the success message
  else
    puts result.failure # Logs the failure message
  end
end

# Logs the total execution time of the script
#
# @param [Float] elapsed_time The total time taken to execute the script, in seconds.
p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to fetch families without determined fa applications. **********"