# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module HbxAdmin
    module DryRun
      module Individual
        # Operation to fetch enrollment states efficiently
        class EnrollmentStates
          include Dry::Monads[:result, :do]

          # @return [Dry::Monads::Result]
          def call
            coverage_years = yield fetch_coverage_years
            year = coverage_years[0]
            enrollment_states = yield fetch_enrollment_states(year)

            Success(enrollment_states)
          end

          private

          def fetch_coverage_years
            benefits_result = ::Operations::HbxAdmin::DryRun::Individual::Benefits.new.call
            return Failure("Failed to get coverage years") if benefits_result.failure?

            _, coverage_years = benefits_result.value!
            Success(coverage_years)
          rescue StandardError => e
            Failure("Coverage years error: #{e.message}")
          end

          def fetch_enrollment_states(year)
            effective_on = Date.new(year, 1, 1)
            enrolled_states = HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES

            # Optimized aggregation pipeline
            enrollment_pipeline = [
              {
                "$match" => {
                  "kind" => "individual",
                  "aasm_state" => {"$in" => enrolled_states},
                  "effective_on" => {"$gte" => effective_on},
                  "coverage_kind" => {"$in" => ["health", "dental"]}
                }
              },
              {
                "$addFields" => {
                  "aptc_category" => {
                    "$cond" => {
                      "if" => {"$and" => [
                        {"$eq" => ["$coverage_kind", "health"]},
                        {"$gt" => ["$applied_aptc_amount", 0]}
                      ]},
                      "then" => "with_aptc",
                      "else" => "without_aptc"
                    }
                  }
                }
              },
              {
                "$group" => {
                  "_id" => {
                    "coverage_kind" => "$coverage_kind",
                    "aasm_state" => "$aasm_state",
                    "aptc_category" => "$aptc_category"
                  },
                  "count" => {"$sum" => 1}
                }
              },
              {
                "$sort" => {
                  "_id.coverage_kind" => 1,
                  "_id.aptc_category" => 1,
                  "_id.aasm_state" => 1
                }
              }
            ]

            # Execute optimized aggregation
            enrollment_states_raw = HbxEnrollment.collection.aggregate(
              enrollment_pipeline,
              allow_disk_use: true,
              batch_size: 1000
            ).to_a

            # Build enrollment states structure efficiently
            enrollment_states = build_enrollment_states_structure(enrollment_states_raw)

            Success(enrollment_states)
          rescue StandardError
            # Return default structure on error
            Success(default_enrollment_states)
          end

          def build_enrollment_states_structure(enrollment_states_raw)
            enrollment_states = default_enrollment_states

            # Map results to structure
            enrollment_states_raw.each do |result|
              coverage_kind = result["_id"]["coverage_kind"]
              aasm_state = result["_id"]["aasm_state"]
              aptc_category = result["_id"]["aptc_category"]
              count = result["count"]

              if coverage_kind == "dental"
                enrollment_states["dental"][aasm_state] = count
              else
                enrollment_states["health"][aptc_category][aasm_state] = count
              end
            end

            enrollment_states
          end

          def default_enrollment_states
            {
              "health" => {
                "without_aptc" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0},
                "with_aptc" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0}
              },
              "dental" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0}
            }
          end
        end
      end
    end
  end
end
