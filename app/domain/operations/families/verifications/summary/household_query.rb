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
            valid_params    = yield validate(params)
            subjects        = yield find_subjects(valid_params)
            action_items    = yield find_action_items_and_sort(subjects)
            sorted_subjects = yield find_subjects_items_and_sort(subjects)

            Success(action_items: action_items, subjects: sorted_subjects)
          end

          private

          def validate(params)
            return Failure("Family is missing") unless params[:family].present?

            Success(params)
          end

          def find_subjects(params)
            family = params[:family]
            ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family) if family.eligibility_determination.nil?
            all_subjects = family.eligibility_determination.subjects

            return Success(all_subjects) if params[:include_inactives] && EnrollRegistry.feature_enabled?(:show_inactive_verification_members)

            members = all_subjects.map { |subject| GlobalID::Locator.locate(subject.gid) }
            return Failure("Family members not found") unless members.count == all_subjects.count

            zipped_subjects = members.map(&:is_active).zip(all_subjects)
            active_subjects = zipped_subjects.select { |active, _| active }.map(&:last)
            Success(active_subjects)
          end

          def find_action_items_and_sort(subjects)
            uploadable_eligibilities = subjects.map do |subject|
              subject.eligibility_states.by_type_uploadable
            end.flatten
            action_items = uploadable_eligibilities.map do |state|
              state.evidence_states.select(&:is_action_needed?)
            end.flatten

            sorted_action_items = action_items.sort_by { |evidence| evidence.due_on || Float::INFINITY }
            Success(sorted_action_items.map { |evidence| ::Adapters::EvidenceAdapter.new(evidence) })
          end

          def find_subjects_items_and_sort(subjects)
            Success(subjects.sort_by do |subject|
              [subject.cumulative_grouped_status.to_s, subject.earliest_due_date || Float::INFINITY]
            end)
          end
        end
      end
    end
  end
end

