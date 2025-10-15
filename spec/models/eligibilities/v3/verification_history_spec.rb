# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::VerificationHistory, type: :model do
  let(:applicant)       { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:evidence)        { FactoryBot.create(:alive_evidence, eligibility: ivl_eligibility) }
  let(:verification_history)  { FactoryBot.create(:v3_verification_history, evidence: evidence) }

  describe 'associations' do
    it 'is embedded in an evidence' do
      expect(verification_history.evidence).to eq(evidence)
    end
  end

  describe 'fields' do
    it { should have_field(:action).of_type(String) }
    it { should have_field(:update_reason).of_type(String) }
    it { should have_field(:updated_by).of_type(String) }
    it { should have_field(:is_satisfied).of_type(Mongoid::Boolean) }
    it { should have_field(:verification_outstanding).of_type(Mongoid::Boolean) }
    it { should have_field(:due_on).of_type(Date) }
  end

  describe 'callbacks' do
    it 'sets date_of_action before create' do
      expect(verification_history.date_of_action).to be_present
    end
  end

  describe 'scopes' do
    let(:evidence_with_histories) { FactoryBot.create(:alive_evidence, eligibility: ivl_eligibility) }

    before do
      # Create verification histories with different attributes
      @history_with_due_date = FactoryBot.create(
        :v3_verification_history,
        evidence: evidence_with_histories,
        due_on: Date.current + 30.days,
        created_at: 2.days.ago
      )

      @history_without_due_date = FactoryBot.create(
        :v3_verification_history,
        evidence: evidence_with_histories,
        due_on: nil,
        created_at: 1.day.ago
      )

      @newest_history = FactoryBot.create(
        :v3_verification_history,
        evidence: evidence_with_histories,
        due_on: Date.current + 60.days,
        created_at: Time.current
      )
    end

    describe '.with_due_date' do
      it 'returns only verification histories with a due date set' do
        results = evidence_with_histories.verification_histories.with_due_date

        expect(results).to include(@history_with_due_date, @newest_history)
        expect(results).not_to include(@history_without_due_date)
        expect(results.count).to eq(2)
      end

      it 'returns empty collection when no histories have due dates' do
        evidence_without_due_dates = FactoryBot.create(:alive_evidence, eligibility: ivl_eligibility)
        FactoryBot.create(:v3_verification_history, evidence: evidence_without_due_dates, due_on: nil)

        results = evidence_without_due_dates.verification_histories.with_due_date

        expect(results).to be_empty
      end
    end

    describe '.newest' do
      it 'returns the most recent verification history based on created_at' do
        result = evidence_with_histories.verification_histories.newest

        expect(result.first).to eq(@newest_history)
        expect(result.count).to eq(1)
      end

      it 'limits results to 1 record for performance optimization' do
        result = evidence_with_histories.verification_histories.newest

        expect(result.count).to eq(1)
        expect(result.first.created_at).to eq(@newest_history.created_at)
      end

      it 'returns empty collection when no histories exist' do
        empty_evidence = FactoryBot.create(:alive_evidence, eligibility: ivl_eligibility)

        result = empty_evidence.verification_histories.newest

        expect(result).to be_empty
      end

      it 'orders by created_at in descending order' do
        middle_history = FactoryBot.create(
          :v3_verification_history,
          evidence: evidence_with_histories,
          created_at: 12.hours.ago
        )

        result = evidence_with_histories.verification_histories.newest

        expect(result.first).to eq(@newest_history)
        expect(result.first).not_to eq(middle_history)
        expect(result.first).not_to eq(@history_with_due_date)
      end
    end

    describe 'scope chaining' do
      it 'can chain with_due_date and newest scopes' do
        result = evidence_with_histories.verification_histories.with_due_date.newest

        expect(result.first).to eq(@newest_history)
        expect(result.count).to eq(1)
      end
    end
  end
end
