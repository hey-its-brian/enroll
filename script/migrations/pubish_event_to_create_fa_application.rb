# Script to determine family eligibility for families with outstanding verifications (OV).
# This script initiates an asynchronous migration to create financial assistance applications
# for families with OV for a specified assistance year.
#
# The migration processes families in batches for efficiency and logs the success or failure
# of the operation along with the total execution time.
#
# @example Run the script
#   #   CLIENT=me bundle exec rails runner script/migrations/pubish_event_to_create_fa_application.rb
#
# @see Operations::AsyncMigrations::InitiateMigration
#   The operation used to initiate the migration process.
#
# @see Caches::BenchmarkCache
#   Utility used to measure the execution time of the script.
#
# @return [void]
p '********** STARTING - Script to create financial assistance applications **********'

# Measures the execution time of the migration process.
elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Parameters for initiating the migration
  #
  # @param [Hash] params The parameters required to initiate the migration.
  # @option params [String] :data_source The source of data for the migration (e.g., 'eligible_family_ids').
  # @option params [String] :migration_handler_name The name of the migration handler (e.g., 'create_financial_assistance_application').
  # @option params [Integer] :batch_size The number of records to process in each batch (default: 3000).
  # @option params [Hash] :additional_params Additional parameters for the migration (e.g., { assistance_year: 2025 }).
  params = {
    data_source: 'latest_determined_fa_application_with_ids', # Specifies the data source for the migration
    migration_handler_name: 'create_financial_assistance_application', # Mapping key for the migration handler
    batch_size: 3000, # Number of records to process in each batch
    additional_params: { assistance_year: 2025 } # Additional parameters for the migration
  }

  # Initiates the migration operation
  #
  # @return [Dry::Monads::Result] The result of the migration operation.
  #   - If successful, returns a success message.
  #   - If failed, returns a failure message.
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
p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to create financial assistance applications. **********"