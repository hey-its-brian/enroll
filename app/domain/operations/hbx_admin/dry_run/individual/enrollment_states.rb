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
            enrollment_states = yield fetch_enrollment_states

            Success(enrollment_states)
          end

          private


          def fetch_enrollment_states
            year = Family.application_applicable_year
            pipeline = ::Operations::HbxAdmin::DryRun::Individual::EnrollmentsPipeline.new.call(effective_on: Date.new(year, 1, 1), aasm_states: HbxEnrollment::ENROLLED_AND_RENEWAL_STATUSES)
            return Success(skeleton_for_enrollments(year)) if pipeline.failure?

            enrollment_states = aggregate_collection(HbxEnrollment.collection, pipeline.value!).to_a

            if enrollment_states.present?
              mapped_data = map_enrollment_kinds(enrollment_states)
              # Debug: Log the structure to help identify issues
              Rails.logger.info "Enrollment States Debug: #{mapped_data.inspect}"
              Success(mapped_data)
            else
              Success(skeleton_for_enrollments(year))
            end
          rescue StandardError => e
            Failure(["fetch_enrollment_states: error: #{e.message}", skeleton(year)])
          end

          def map_enrollment_kinds(enrollment_states)
            # Start with skeleton data to ensure all rows are always shown
            result = skeleton_for_enrollments(Family.application_applicable_year)

            enrollment_states.each do |hash|
              coverage_kind = hash["coverage_kind"]
              without_aptc = hash['without_aptc'] || {}
              with_aptc = hash['with_aptc'] || {}

              if coverage_kind == "dental"
                # For dental, merge both without_aptc and with_aptc into a single structure
                # since dental doesn't have APTC, but we want to show all states
                dental_data = without_aptc.merge(with_aptc)
                result[coverage_kind] = dental_data
              else
                # For health, keep the nested structure
                result[coverage_kind] = { "without_aptc" => without_aptc, "with_aptc" => with_aptc }
              end
            end

            result
          end

          def aggregate_collection(collection, pipeline)
            collection.aggregate(pipeline).to_a
          end

          def skeleton_for_enrollments(_year)
            {
              "health" => {
                "without_aptc" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0},
                "with_aptc" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0}
              },
              "dental" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0}
            }
          end

          def skeleton(year)
            skeleton_for_enrollments(year)
          end
        end
      end
    end
  end
end
