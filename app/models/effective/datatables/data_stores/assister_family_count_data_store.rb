# frozen_string_literal: true

module Effective
  module Datatables
    module DataStores
      # DataStore responsible for managing and providing data related to active family counts under Assister Agencies.
      class AssisterFamilyCountDataStore < Effective::Datatables::DataStores::BaseDataStore
        # Returns the model class associated with this data store.
        #
        # @return [Class] the Family model class
        def self.model_class
          Family
        end

        # Returns the symbol representing the method to count assister agency profiles.
        #
        # @return [Symbol] the method name :assister_agency_profile_counts
        def self.model_method
          :assister_agency_profile_counts
        end

        # Returns the default value for the projected assister agency profile family count.
        #
        # @return [Integer] 0
        def self.cached_data_field_default_value
          0
        end

        # Sets the hash for the family count data store if the assister family count feature is enabled.
        # This method overrides the superclass method and only calls `super` if the feature is enabled.
        #
        # @return [void]
        def self.compute_cache
          return unless EnrollRegistry.feature_enabled?(:broker_family_count)
          super
        end
      end
    end
  end
end
