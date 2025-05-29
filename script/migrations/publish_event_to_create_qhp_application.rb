
p '********** STARTING - Script to fetch families without determined fa applications **********'

# Measures the execution time of the migration process.
elapsed_time = Caches::BenchmarkCache.with_benchmark do

  params = {
    data_source: 'families_without_determined_fa_applications_for_current_year', # Specifies the data source for the migration
    migration_handler_name: 'create_qhp_application', # Mapping key for the migration handler
    batch_size: 3000, # Number of records to process in each batch
    additional_params: { assistance_year: 2025 } # Additional parameters for the migration
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