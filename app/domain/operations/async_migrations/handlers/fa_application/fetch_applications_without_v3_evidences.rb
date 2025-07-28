# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module FAApplication
        # This operation fetches all Financial Assistance applications for the given aasm_state
        # This operation can be retriggered multiple times, and it will only return applications that do not have v3 eligibilities.
        class FetchApplicationsWithoutV3Evidences
          include Dry::Monads[:do, :result]

          AASM_STATES_MAPPINGS = [
                                  "draft",
                                  "determined",
                                  'submitted',
                                  'renewal_draft',
                                  'income_verification_extension_required',
                                  'applicants_update_required',
                                  'cancelled'
                                 ].freeze

          # Fetches Financial Assistance applications for specified AASM states.
          #
          # @param params [Hash] input parameters containing additional_params
          # @option params [Hash] :additional_params nested parameters hash
          # @option params [Array<String>] :aasm_states (via additional_params) the AASM states to filter by
          # @return [Dry::Monads::Result] Success with application IDs or Failure with error message
          #
          # @raise [StandardError] if database query fails
          def call(params)
            aasm_states = yield validate(params)
            yield fetch_applications(aasm_states)
          end

          private

          # Validates the input parameters to ensure required aasm_states is present and valid.
          #
          # @param params [Hash] input parameters
          # @return [Dry::Monads::Result] Success with aasm_states array or Failure with error message
          #
          # @example Valid parameters
          #   validate({ additional_params: { aasm_states: ["draft"] } })
          #   # => Success(["draft"])
          #
          # @example Invalid parameters - empty params
          #   validate({})
          #   # => Failure("Invalid params: aasm_states not provided")
          #
          # @example Invalid parameters - non-array aasm_states
          #   validate({ additional_params: { aasm_states: "draft" } })
          #   # => Failure("Invalid aasm_states: must be an array")
          def validate(params)
            return Failure("Invalid params: aasm_states not provided") if invalid_params?(params)

            aasm_states = params[:additional_params][:aasm_states]
            return Failure("Invalid aasm_states: must be an array") unless aasm_states.is_a?(Array)

            Success(aasm_states)
          end

          # Fetches Financial Assistance applications that match the specified AASM states
          #
          # @param aasm_states [Array<String>] the AASM states to filter applications by
          # @return [Dry::Monads::Result] Success with application IDs or Failure with error message
          # @note The query only returns :hbx_id and :aasm_state fields for performance
          def fetch_applications(aasm_states)
            return Failure("Invalid aasm_states provided") if aasm_states.empty? || (aasm_states & AASM_STATES_MAPPINGS).empty?
            aasm_states &= AASM_STATES_MAPPINGS

            result = ::FinancialAssistance::Application
                     .only(:aasm_state, :applicants, :_id, :hbx_id)
                     .where({
                              aasm_state: { '$in' => aasm_states },
                              'applicants.eligibilities.0': { '$exists' => false },
                              applicants: {
                                '$elemMatch' => {
                                  '$or' => [
                                    { income_evidence: { :$exists => true } },
                                    { esi_evidence: { :$exists => true } },
                                    { non_esi_evidence: { :$exists => true } },
                                    { local_mec_evidence: { :$exists => true } }
                                  ]
                                }
                              }
                            })
                     .pluck(:_id)
            Success(result)
          rescue StandardError => e
            Failure("Error fetching applications: #{e.message}")
          end

          # Checks if the provided parameters are invalid
          #
          # @param params [Hash] input parameters to validate
          # @return [Boolean] true if parameters are invalid, false otherwise
          def invalid_params?(params)
            params.empty? ||
              params[:additional_params].nil? ||
              params[:additional_params][:aasm_states].nil?
          end

          # Builds the MongoDB query for filtering applications
          #
          # @param aasm_states [Array<String>] the AASM states to filter by
          # @return [Hash] MongoDB query hash
          def build_query(aasm_states)
            {
              aasm_state: { '$in' => aasm_states },
              'applicants.eligibilities.0': { '$exists' => false },
              applicants: {
                '$elemMatch' => {
                  '$or' => [
                    { income_evidence: { :$exists => true } },
                    { esi_evidence: { :$exists => true } },
                    { non_esi_evidence: { :$exists => true } },
                    { local_mec_evidence: { :$exists => true } }
                  ]
                }
              }
            }
          end
        end
      end
    end
  end
end
