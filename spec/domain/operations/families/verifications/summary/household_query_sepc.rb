# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Families::Verifications::Summary::HouseholdQuery do
  subject { described_class.new }

  describe '#call' do
    context 'when params are invalid' do
      let(:params) { {} }

      it 'returns failure when family is missing' do
        result = subject.call(params)
        expect(result).to be_failure
        expect(result.failure).to eq('Family is missing')
      end
    end

    context 'with valid params' do
      let(:family) { create(:family, :with_primary_family_member, :with_eligibility_determination) }
      let(:params) { { family: family } }

      before do
        # Mock the EvidenceAdapter to avoid having to implement it for tests
        allow(::Adapters::EvidenceAdapter).to receive(:new) do |evidence|
          # Return a simple object with the original evidence accessible
          OpenStruct.new(original_evidence: evidence, due_on: evidence.due_on)
        end
      end

      it 'returns successful response with action_items and subjects' do
        result = subject.call(params)
        expect(result).to be_success
        expect(result.success).to have_key(:action_items)
        expect(result.success).to have_key(:subjects)
      end

      it 'returns subjects from the family eligibility determination' do
        result = subject.call(params)
        expect(result.success[:subjects]).to match_array(family.eligibility_determination.subjects)
      end

      it 'finds action items that need attention' do
        result = subject.call(params)

        # Verify there are action items when we expect them
        expect(result.success[:action_items]).not_to be_empty if family.eligibility_determination.subjects.any?(&:documents_outstanding?)
      end

      context 'with multiple subjects that have varying document requirements' do
        let(:family) do
          create(:family,
                 :with_primary_family_member,
                 :with_eligibility_determination,
                 subject_count: 3,
                 subjects_with_action_needed: 2)
        end

        it 'sorts subjects with outstanding documents first' do
          result = subject.call(params)
          subjects = result.success[:subjects]

          # Check that the first elements have documents_outstanding? == true
          outstanding_subjects = subjects.select(&:documents_outstanding?)
          non_outstanding_subjects = subjects.reject(&:documents_outstanding?)

          if outstanding_subjects.any? && non_outstanding_subjects.any?
            # All outstanding subjects should come before non-outstanding subjects
            last_outstanding_index = subjects.index(outstanding_subjects.last)
            first_non_outstanding_index = subjects.index(non_outstanding_subjects.first)
            expect(last_outstanding_index).to be < first_non_outstanding_index
          end
        end
      end

      context 'with evidence items that have different due dates' do
        let(:family) do
          create(:family,
                 :with_primary_family_member,
                 :with_eligibility_determination,
                 subject_count: 2,
                 subjects_with_action_needed: 2)
        end

        let(:all_evidence_states) do
          family.eligibility_determination.subjects.flat_map do |subject|
            subject.eligibility_states.flat_map(&:evidence_states)
          end
        end

        let(:action_needed_evidence) do
          all_evidence_states.select(&:is_action_needed?)
        end

        it 'sorts action items by due date' do
          result = subject.call(params)
          action_items = result.success[:action_items]

          due_dates = action_items.map(&:original_evidence).map(&:due_on).compact
          expect(due_dates).to eq(due_dates.sort)
        end
      end

      context 'with evidence items that have varying statuses' do
        let(:expected_status_counts) do
          {
            "action_needed" => 2,
            "review" => 5,
            "verified" => 3
          }
        end
        let(:family) do
          create(:family,
                 :with_primary_family_member,
                 :with_eligibility_determination,
                 subject_count: expected_status_counts.values.sum,
                 subjects_with_action_needed: expected_status_counts["action_needed"],
                 subjects_with_review: expected_status_counts["review"])
        end

        it 'should return 2 action items' do
          result = subject.call(params)
          action_items = result.success[:action_items]
          expect(action_items.size).to eq(2)
        end

        it 'should return subjects with statuses "action_needed", "review", and "verified"' do
          result = subject.call(params)
          subjects = result.success[:subjects]

          statuses = subjects.reduce({}) do |acc, subject|
            status_key = subject.cumulative_grouped_status.to_s
            acc[status_key] = acc.fetch(status_key, 0) + 1
            acc
          end
          expect(statuses).to eq(expected_status_counts)
        end
      end
    end
  end
end
