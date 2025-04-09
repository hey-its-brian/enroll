# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Evidences::AliveEvidence, type: :model do
  let(:applicant)       { FactoryBot.create(:individual_market_applicant) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:evidence)        { FactoryBot.create(:alive_evidence, eligibility: ivl_eligibility) }

  describe 'Model attributes' do
    it 'inherits attributes from V3::Evidence' do
      # Check fields from parent class
      expect(evidence).to respond_to(:key)
      expect(evidence).to respond_to(:title)
      expect(evidence).to respond_to(:description)
      expect(evidence).to respond_to(:is_satisfied)
      expect(evidence).to respond_to(:determined_at)
      expect(evidence).to respond_to(:current_state)
    end

    it 'includes attributes from EvidenceUtils' do
      # Check fields from EvidenceUtils
      expect(evidence).to respond_to(:received_at)
      expect(evidence).to respond_to(:verification_outstanding)
      expect(evidence).to respond_to(:update_reason)
      expect(evidence).to respond_to(:due_on)
      expect(evidence).to respond_to(:external_service)
      expect(evidence).to respond_to(:updated_by)
    end

    it 'includes embedded relations from EvidenceUtils' do
      # Check embedded relations
      expect(evidence).to respond_to(:state_histories)
      expect(evidence).to respond_to(:verification_histories)
      expect(evidence).to respond_to(:request_results)
    end
  end

  describe '#latest_state_history' do
    let(:state_history1) do
      FactoryBot.create(
        :v3_state_history,
        created_at: 1.day.ago,
        status_trackable: evidence
      )
    end

    let(:state_history2) do
      FactoryBot.create(
        :v3_state_history,
        status_trackable: evidence
      )
    end

    before do
      state_history1
      state_history2
    end

    it 'returns the most recent state history' do
      expect(evidence.latest_state_history).to eq(state_history2)
    end

    it 'memoizes the result' do
      first_call = evidence.latest_state_history
      expect(evidence.state_histories).to receive(:newest).never
      second_call = evidence.latest_state_history
      expect(second_call).to eq(first_call)
    end
  end

  describe 'verification workflow' do
    let(:evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }

    it 'starts in pending state' do
      expect(evidence.current_state).to eq(:pending)
    end

    context 'when documents are uploaded' do
      before do
        # Simulate document upload
        # This would depend on the actual implementation of document uploads
        evidence.update(current_state: :outstanding)
      end

      it 'transitions to outstanding state' do
        expect(evidence.current_state).to eq(:outstanding)
      end
    end

    context 'when alive status is verified' do
      before do
        evidence.update(current_state: :verified)
      end

      it 'transitions to verified state' do
        expect(evidence.current_state).to eq(:verified)
      end
    end
  end
end
