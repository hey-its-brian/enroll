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
            # Fetch all matching applications in a single query
            applications = ::FinancialAssistance::Application.where(
              :assistance_year.in => coverage_years,
              generation_reason: :renewal,
              origin: :system
            ).only(:assistance_year, :aasm_state)

            # Group by year and state in memory
            grouped_data = applications.each_with_object(Hash.new { |h, k| h[k] = Hash.new(0) }) do |app, hash|
              hash[app.assistance_year][app.aasm_state.to_s] += 1
            end

            # Build response structure
            mapped_states = coverage_years.map do |assistance_year|
              states_hash = {}

              ::FinancialAssistance::Application.aasm.states.map(&:name).each do |state_name|
                states_hash[state_name.to_s] = grouped_data.dig(assistance_year, state_name.to_s) || 0
              end

              {"assistance_year" => assistance_year, "application_states" => states_hash}
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