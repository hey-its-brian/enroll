# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        module Eligibility
          # Handler to remove family eligibility determinations.
          class Remove
            include Dry::Monads[:do, :result]
            include ::ResourceRegistryHelper

            # Removes family eligibility for the given family document ID.
            #
            # @param document_id [String] The document ID of the family to remove eligibility for.
            # @return [Dry::Monads::Result] The result of the operation.
            def call(params)
              family_id = yield validate(params)
              family = yield find_family(family_id)
              remove_determination(family)
            end

            private

            # Validates the input parameters.
            #
            # @param document_id [String] The document ID to validate.
            # @return [Dry::Monads::Result] The result of the validation.
            def validate(params)
              return Failure("qhp_application_feature flag is not enabled") unless qhp_application_feature_enabled?
              return Failure("Params must be a hash") unless params.is_a?(Hash)
              return Failure("Document id must be of valid BSON::ObjectId format") unless BSON::ObjectId.legal?(params[:document_id])

              Success(params[:document_id])
            end

            def find_family(family_id)
              Success(Family.only(:_id, :eligibility_determination).where(:id => family_id).first)
            end

            def remove_determination(family)
              return Success("No eligibility determination to remove") unless family.eligibility_determination

              family.eligibility_determination.destroy
              Success("Removed eligibility determination for family: #{family.id}")
            rescue StandardError => e
              Failure("Failed to remove eligibility determination: #{e.message}")
            end
          end
        end
      end
    end
  end
end
