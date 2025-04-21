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
        'families_with_id' => ::Family.only(:_id)
      }.freeze

      # Mapping of event handler names to their corresponding classes.
      #
      # @return [Hash] The mapping of event handler names to their corresponding classes.
      EVENT_HANDLER_MAP = {
        '::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility' => ::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility
      }.freeze
    end
  end
end
