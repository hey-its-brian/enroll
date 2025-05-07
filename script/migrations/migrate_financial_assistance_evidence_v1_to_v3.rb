# Script to determine family eligibility for applications with outstanding verifications (OV).
# This script initiates an asynchronous migration to migrate evidence from version 1 to version 3.
#
# @example Running the script
#   CLIENT=me bundle exec rails runner script/migrations/migrate_financial_assistance_evidence_v1_to_v3.rb
#
# @note The script uses a batch size of 3000 for processing applications.
#
# @see Operations::AsyncMigrations::InitiateMigration
# @see Operations::AsyncMigrations::Handlers::FAApplications::MigrateEvidence
#
# @return [void]
#   Outputs the success or failure message of the migration operation.
p '********** STARTING - Script to migrate financial assistance evidence v1 to v3 **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Parameters for initiating the migration
  params = {
    data_source: 'applications_with_aasm_state_and_hbx_ids', # Specifies the data source for the migration
    migration_handler_name: 'migrate_fa_evidences', # Mapping key for the migration handler
    batch_size: 3000 # Number of records to process in each batch
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

p "********** FINISHED in #{elapsed_time.ceil} seconds - Script to migrate financial assistance evidence v1 to v3. **********"