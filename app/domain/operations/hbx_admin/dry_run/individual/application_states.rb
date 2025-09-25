# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module HbxAdmin
    module DryRun
      module Individual
        # Operation to fetch application states and eligible families efficiently
        class ApplicationStates
          include Dry::Monads[:result, :do]

          APPLICATION_STATES = ::FinancialAssistance::Application.all_aasm_states.map(&:to_s).freeze

          # @return [Dry::Monads::Result]
          def call
            coverage_years = yield fetch_coverage_years
            renewal_year = coverage_years[0]

            eligible_families = yield fetch_eligible_families(renewal_year)
            application_states = yield fetch_application_states(coverage_years)

            Success({
                      eligible_families: eligible_families,
                      application_states: application_states,
                      renewal_year: renewal_year
                    })
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

          def fetch_eligible_families(renewal_year)
            # Families with renewal_year.pred active enrollments
            family_ids = ::HbxEnrollment.collection.aggregate([
              {
                "$match" => {
                  "kind" => "individual",
                  "aasm_state" => {"$in" => %w[coverage_selected auto_renewing renewing_coverage_selected]},
                  "effective_on" => {"$gte" => Date.new(renewal_year.pred, 1, 1)}
                }
              },
              {
                "$group" => {
                  "_id" => "$family_id"
                }
              }
            ], allow_disk_use: true, max_time_ms: 15_000).map { |doc| doc["_id"] }

            # Families with renewal_year.pred financial assistance applications
            family_ids_with_prev_year_fa_apps = ::FinancialAssistance::Application.where(
              assistance_year: renewal_year.pred,
              aasm_state: "determined",
              :family_id.in => family_ids
            ).distinct(:family_id)

            # Families with latest_application_gid pointing to a FA application
            eligible_count = ::Family.where(
              :_id.in => family_ids_with_prev_year_fa_apps,
              latest_application_gid: %r{gid://enroll/FinancialAssistance::Application/}
            ).count

            Success({ 'families_eligible_for_application_renewal' => eligible_count })
          rescue StandardError => e
            Failure("Eligible families error: #{e.message}")
          end

          def fetch_application_states(coverage_years)
            # Optimized aggregation pipeline
            application_pipeline = [
              {"$match" => {
                "assistance_year" => {"$in" => coverage_years},
                "predecessor_id" => {"$exists" => true, "$ne" => nil}
              }},
              {"$group" => {
                "_id" => {"assistance_year" => "$assistance_year", "aasm_state" => "$aasm_state"},
                "count" => {"$sum" => 1}
              }},
              {"$sort" => {"_id.assistance_year" => -1}}
            ]

            application_states_raw = ::FinancialAssistance::Application.collection.aggregate(
              application_pipeline,
              allow_disk_use: true,
              batch_size: 1000,
              max_time_ms: 20_000
            ).to_a

            # Map states to years
            mapped_states = coverage_years.map do |year|
              year_states = application_states_raw.select { |state| state['_id']['assistance_year'] == year }
              states_hash = year_states.each_with_object({}) do |state, hash|
                hash[state['_id']['aasm_state']] = state['count']
              end

              # Ensure all states are represented
              APPLICATION_STATES.each do |state|
                states_hash[state] ||= 0
              end

              {"assistance_year" => year, "application_states" => states_hash}
            end

            Success(mapped_states)
          rescue StandardError => e
            Failure("Application states error: #{e.message}")
          end
        end
      end
    end
  end
end