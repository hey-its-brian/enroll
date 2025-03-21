# frozen_string_literal: true

module Operations
  module Families
    module Verifications
      module Summary
        # Retrieves and organizes household verification data for display in the verification summary view.
        # This query only collects verification data from the eligiblity determination, not other sources which
        # are assumed to be un-actionable, like Identity verification.
        #
        # @see EvidenceAdapter Used to normalize evidence states for consistent display
        class HouseholdQuery
          include Dry::Monads[:do, :result]

          def call(params)
            valid_params = yield validate(params)
            family = valid_params[:family]
            action_items = yield find_action_items_and_sort(family)
            subjects     = yield find_subjects_items_and_sort(family)

            Success(action_items: action_items, subjects: subjects)
          end

          private

          def validate(params)
            return Failure("Family is missing") unless params[:family].present?

            Success(params)
          end

          def find_action_items_and_sort(family)
            uploadable_eligibilities = family.eligibility_determination.subjects.map do |subject|
              subject.eligibility_states.by_type_uploadable
            end.flatten
            action_items = uploadable_eligibilities.map do |state|
              state.evidence_states.where_action_needed
            end.flatten

            sorted_action_items = action_items.sort_by { |evidence| evidence.due_on || Float::INFINITY }
            Success(sorted_action_items.map { |evidence| ::Adapters::EvidenceAdapter.new(evidence) })
          end

          def find_subjects_items_and_sort(family)
            Success(family.eligibility_determination.subjects.sort_by do |subject|
              [subject.documents_outstanding? ? 0 : 1, subject.earliest_due_date || Float::INFINITY]
            end)
          end
        end
      end
    end
  end
end
