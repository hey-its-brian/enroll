# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module HbxAdmin
    module DryRun
      module Individual
        # Operation to fetch application states and eligible families efficiently
        class QhpApplicationStates
          include Dry::Monads[:result, :do]

          APPLICATION_STATES = ::IndividualMarket::Application::STATES.freeze

          def call
            coverage_years      = yield fetch_coverage_years
            application_states  = yield fetch_application_states(coverage_years)

            Success(application_states)
          end

          private

          # Fetches eligible coverage years based on the system date.
          def fetch_coverage_years
            benefits_result = ::Operations::HbxAdmin::DryRun::Individual::Benefits.new.call
            return Failure("Failed to get coverage years") if benefits_result.failure?

            _, coverage_years = benefits_result.value!
            Success(coverage_years)
          rescue StandardError => e
            Failure("Coverage years error: #{e.message}")
          end

          # Optimized aggregation for QHP application states
          #
          # @return [Dry::Monads::Result]
          def fetch_application_states(coverage_years)
            applications = ::IndividualMarket::Application.only(
              :assistance_year, :current_state
            ).where(:assistance_year.in => coverage_years, :is_renewal => true)

            mapped_states = coverage_years.inject([]) do |result, year|
              result << {
                assistance_year: year,
                application_states: APPLICATION_STATES.each_with_object({}) do |state, hash|
                  hash[state] = applications.where(assistance_year: year, current_state: state).count
                end
              }
              result
            end

            Success({ application_states: mapped_states })
          rescue StandardError => e
            Failure("Application states error: #{e.message}")
          end
        end
      end
    end
  end
end
