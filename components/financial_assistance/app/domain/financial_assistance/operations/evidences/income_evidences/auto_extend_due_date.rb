# frozen_string_literal: true

module FinancialAssistance
  module Operations
    module Evidences
      module IncomeEvidences
        # This operation automatically extends the due date for income evidences for specific families. Families are selected based on a criteria.
        class AutoExtendDueDate
          include Dry::Monads[:do, :result]

          def call(params)
            validated_params  = yield validate_input_params(params)
            eligible_families = yield fetch_families(validated_params[:current_due_on])
            updated_result    = yield auto_extend_due_date(eligible_families, validated_params[:extend_by], validated_params[:modified_by])

            Success(updated_result)
          end

          private

          # Validates the input parameters for the operation
          #
          # @param params [Hash] The input parameters
          # @option params [Date] :current_due_on (optional) The due date of the income evidence to query
          # @option params [Integer] :extend_by (optional) Number of days to extend the due date by
          # @option params [String] :modified_by (optional) Identifier of the user or process that modified the due
          #
          # @return [Success] A hash with validated parameters
          # @return [Failure] An error message if validation fails
          def validate_input_params(params)
            current_due_on = params[:current_due_on] || TimeKeeper.date_of_record
            extend_by = params[:extend_by] || FinancialAssistanceRegistry[:auto_update_income_evidence_due_on].settings(:days).item
            modified_by = params[:modified_by] || 'system'

            return Failure('Invalid param for key current_due_on, must be a Date') unless current_due_on.is_a?(Date)
            return Failure('Invalid param for key extend_by, must be an Integer') unless extend_by.is_a?(Integer) && extend_by.positive?
            return Failure('Invalid param for key modified_by, must be a String') unless modified_by.is_a?(String)

            Success({ current_due_on: current_due_on, extend_by: extend_by, modified_by: modified_by })
          end

          # Finds families with outstanding income evidence due on the specified date
          #
          # @param current_due_on [Date] The date for which to find families with outstanding income evidence
          #
          # @return [Success] A collection of families with outstanding income evidence
          def fetch_families(current_due_on)
            Success(Family.with_outstanding_income_evidence(current_due_on).only(:eligibility_determination, :_id, :latest_application_gid))
          end

          # Extends the income evidence due date for each family
          #
          # @param families [Array<Family>] The families to process
          # @param extend_by [Integer] Number of days to extend the due date by
          # @param modified_by [String] Identifier of the user or process that modified the due
          #
          # @return [Hash] A hash with family IDs as keys and success messages as values
          def auto_extend_due_date(families, extend_by, modified_by)
            Success(
              families.inject({}) do |results, family|
                application = family.latest_application
                if family.latest_application_type == 'faa'
                  application.extend_income_evidence_due_dates('auto_extend_due_date', extend_by, modified_by)
                  application.save!

                  results[family.id] = "Income evidence due date extended for family #{family.id}"
                else
                  results[family.id] = "The latest application is not of type 'faa' for family #{family.id}"
                end
                results
              rescue StandardError => e
                results[family.id] = "Failed to extend income evidence due date for family #{family.id}: #{e.message}"
                Rails.logger.error("Error extending income evidence due date for family #{family.id}: #{e.message}, #{e.backtrace.join("\n")}")
                results
              end
            )
          end
        end
      end
    end
  end
end
