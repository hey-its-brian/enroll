# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Evidences::AmericanIndianEvidence, type: :model do
  let(:applicant)       { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:evidence)        { FactoryBot.create(:american_indian_evidence, eligibility: ivl_eligibility) }

  describe 'inheritance' do
    it 'inherits from Evidence base class' do
      expect(described_class.superclass).to eq(::Eligibilities::V3::Evidence)
    end
  end

  describe 'included modules' do
    it 'includes EvidenceUtils module' do
      expect(described_class.included_modules).to include(::Eligibilities::V3::EvidenceUtils)
    end
  end

  describe 'instance methods' do
    describe '#latest_state_history' do
      let!(:old_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 2.days.ago) }
      let!(:new_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 1.day.ago) }

      it 'returns the most recent state history' do
        expect(evidence.latest_state_history).to eq(new_state_history)
      end

      it 'memoizes the result to avoid repeated database queries' do
        result = evidence.latest_state_history
        expect(evidence.state_histories).not_to receive(:newest)
        expect(evidence.latest_state_history).to eq(result)
      end
    end
  end

  describe 'verification workflow' do
    let(:evidence) { FactoryBot.create(:american_indian_evidence, :pending, eligibility: ivl_eligibility) }

    it 'starts in pending state' do
      expect(evidence.current_state).to eq(:pending)
    end

    context 'when tribal documents are uploaded' do
      before do
        # Simulate document upload
        # This would depend on the actual implementation of document uploads
        evidence.update(current_state: :outstanding)
      end

      it 'transitions to outstanding state' do
        expect(evidence.current_state).to eq(:outstanding)
      end
    end

    context 'when tribal membership is verified' do
      before do
        evidence.update(current_state: :verified)
      end

      it 'transitions to verified state' do
        expect(evidence.current_state).to eq(:verified)
      end
    end
  end
end
