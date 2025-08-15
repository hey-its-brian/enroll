# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        module Eligibility
          # Fetch families with eligibility determinations.
          class FetchFamiliesWithEligibilityDetermination
            include Dry::Monads[:do, :result]

            def call(_params)
              yield families_with_eligibility_determination
            end

            private

            # Since the batch requester is expecting an operation, we cannot use the query directly in the mappings file
            def families_with_eligibility_determination
              Success(Family.where(:eligibility_determination.exists => true).only(:_id).pluck(:id))
            end
          end
        end
      end
    end
  end
end