# Script to determine family eligibility for applications with outstanding verifications (OV).
# This script initiates an asynchronous migration to migrate evidence from version 1 to version 3.
#
# @example Running the script
#   CLIENT=me bundle exec rails runner script/migrations/migrate_financial_assistance_evidence_v1_to_v3.rb [<aasm_state>] [<batch_size>]
#   CLIENT=me bundle exec rails runner script/migrations/migrate_financial_assistance_evidence_v1_to_v3.rb renewal_draft,cancelled,income_verification_extension_required,submitted,applicants_update_required 500 'Array'
# @note The script uses a batch size of 3000 for processing applications.
#
# @see Operations::AsyncMigrations::InitiateMigration
# @see Operations::AsyncMigrations::Handlers::FAApplications::MigrateEvidence
#
# @return [void]
#   Outputs the success or failure message of the migration operation.
p '********** STARTING - Script to migrate financial assistance evidence v1 to v3 **********'

elapsed_time = Caches::BenchmarkCache.with_benchmark do
  # Parameters for reducing the records size
  aasm_states = ARGV[0].present? ? ARGV[0].split(',') : nil
  batch_size = ARGV[1].present? ? ARGV[1].to_i : 3000
  data_type = ARGV[2].present? ? ARGV[2].to_s : nil

  params = {
    data_source: 'applications_with_aasm_state_and_hbx_ids', # Specifies the data source for the migration
    migration_handler_name: 'migrate_fa_evidences', # Mapping key for the migration handler
    batch_size: batch_size, # Number of records to process in each batch
    additional_params: { aasm_states: aasm_states, data_type: data_type } # Additional parameters for the migration
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
