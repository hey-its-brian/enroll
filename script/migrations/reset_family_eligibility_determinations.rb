# This script initiates an asynchronous migration to remove family eligibility determinations.
#
# @example Running the script
#   CLIENT=me bundle exec rails runner script/migrations/reset_family_eligibility_determinations.rb [<batch_size>]
#   CLIENT=me bundle exec rails runner script/migrations/reset_family_eligibility_determinations.rb 3000 'Array'
# @note The script uses a batch size of 3000 for processing applications.
#
# @see Operations::AsyncMigrations::InitiateMigration
# @see ::Operations::AsyncMigrations::Handlers::Families::Eligibility::Remove
#
# @return [void]
#   Outputs the success or failure message of the migration operation.
p '********** STARTING - Script to remove family eligibility determinations **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Parameters for reducing the records size
  batch_size = ARGV[0].present? ? ARGV[0].to_i : 3000
  data_type = ARGV[1].present? ? ARGV[1].to_s : nil

  params = {
    data_source: 'fetch_family_ids_with_eligibility_determination', # Specifies the data source for the migration
    migration_handler_name: 'remove_family_eligibility', # Mapping key for the migration handler
    batch_size: batch_size, # Number of records to process in each batch
    additional_params: { data_type: data_type } # Additional parameters for the migration
  }

  # Initiates the migration operation
  result = ::Operations::AsyncMigrations::InitiateMigration.new.call(params)

  # Outputs the result of the migration
  if result.success?
    puts result.success
  else
    puts result.failure
  end
end

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to remove family eligibility determinations **********"
