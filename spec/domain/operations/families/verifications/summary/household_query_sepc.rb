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
                 subjects_with_outstanding: 2)
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
                 subjects_with_outstanding: 2)
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
    end
  end
end
