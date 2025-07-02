# frozen_string_literal: true

module Operations
  module AsyncMigrations
    # Mappings for string representations of classes to actual classes used in async migrations.
    # Predefined mappings avoid the use of the problematic/unsafe `constantize` method when sending class names over the wire.
    module Mappings
      # Mapping of model or query names  to their corresponding classes.
      #
      # @return [Hash] The mapping of model or query names to their corresponding classes.
      QUERY_MAP = {
        'families_with_id' => ::Family.only(:_id),
        'applications_with_aasm_state_and_hbx_ids' => ::FinancialAssistance::Application.where(:aasm_state.nin => ["imported"]).only(:hbx_id, :aasm_state),
        'latest_determined_fa_application_with_ids' => ::Operations::AsyncMigrations::Handlers::Families::FetchLatestDeterminedFAApplicationHbxIds.new,
        'families_without_determined_fa_applications_for_current_year' => ::Operations::AsyncMigrations::Handlers::Families::FetchFamiliesWithoutDeterminedFAApplication.new,
        'families_with_tax_household_groups' => Family.exists(:tax_household_groups => true).only(:_id)
      }.freeze

      # Mapping of event handler names to their corresponding classes.
      #
      # @return [Hash] The mapping of event handler names to their corresponding classes.
      EVENT_HANDLER_MAP = {
        '::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility' => ::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility,
        '::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibilityUnconditionally' => ::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibilityUnconditionally,
        'migrate_fa_evidences' => ::Operations::AsyncMigrations::Handlers::FAApplication::MigrateEvidence,
        'create_financial_assistance_application' => ::Operations::AsyncMigrations::Handlers::FAApplication::CreateApplication,
        'create_qhp_application' => ::Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::CreateApplication,
        'migrate_tax_household_group' => ::Operations::AsyncMigrations::Handlers::Families::MigrateTaxHouseholdGroup
      }.freeze
    end
  end
end
