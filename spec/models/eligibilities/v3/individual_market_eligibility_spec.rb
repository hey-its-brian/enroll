# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::IndividualMarketEligibility, type: :model do
  let(:applicant)   { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }

  describe 'inheritance' do
    it 'inherits from Eligibilities::V3::Eligibility' do
      expect(described_class.superclass).to eq(Eligibilities::V3::Eligibility)
    end
  end

  describe 'associations' do
    it { should embed_many(:state_histories) }
    it { should embed_many(:determinations) }
    it { should embed_many(:evidences) }
  end

  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_uniqueness_of(:key) }
  end

  describe 'default values' do
    it 'sets current_state to initial by default' do
      expect(eligibility.current_state).to eq(:initial)
    end

    it 'sets is_satisfied to false by default' do
      expect(eligibility.is_satisfied).to be false
    end

    it 'sets is_disqualified to false by default' do
      expect(eligibility.is_disqualified).to be false
    end
  end

  describe '#unique_evidences validation' do
    context 'when there are duplicate evidence types' do
      before do
        evidence_type = 'Eligibilities::V3::Evidence::SocialSecurityNumber'
        2.times do
          evidence = FactoryBot.build(:v3_evidence, _type: evidence_type)
          eligibility.evidences << evidence
        end
      end

      it 'is invalid' do
        expect(eligibility).not_to be_valid
        expect(eligibility.errors[:evidences]).to include('cannot have duplicate evidence types')
      end
    end

    context 'when there are no duplicate evidence types' do
      before do
        eligibility.evidences << FactoryBot.build(:v3_evidence, _type: 'Eligibilities::V3::Evidence::SocialSecurityNumber')
        eligibility.evidences << FactoryBot.build(:v3_evidence, _type: 'Eligibilities::V3::Evidence::CitizenshipStatus')
      end

      it 'is valid' do
        expect(eligibility).to be_valid
      end
    end
  end

  describe 'state histories' do
    it 'can track state transitions' do
      state_history = FactoryBot.build(:v3_state_history, from_state: :initial, to_state: :eligible)
      eligibility.state_histories << state_history

      expect(eligibility.state_histories.count).to eq(1)
      expect(eligibility.state_histories.first.from_state).to eq(:initial)
      expect(eligibility.state_histories.first.to_state).to eq(:eligible)
    end

    it 'can have multiple state transitions' do
      eligibility.state_histories << FactoryBot.build(:v3_state_history, from_state: :initial, to_state: :pending)
      eligibility.state_histories << FactoryBot.build(:v3_state_history, from_state: :pending, to_state: :eligible)

      expect(eligibility.state_histories.count).to eq(2)
      expect(eligibility.state_histories.last.to_state).to eq(:eligible)
    end
  end

  describe 'evidence management' do
    it 'can have multiple evidences' do
      eligibility.evidences << FactoryBot.build(:v3_evidence, key: :citizenship)
      eligibility.evidences << FactoryBot.build(:v3_evidence, key: :income)

      expect(eligibility.evidences.count).to eq(2)
      expect(eligibility.evidences.map(&:key)).to contain_exactly('citizenship', 'income')
    end
  end

  describe "#enrollment_changes" do
    let(:alive_evidence)   { FactoryBot.create(:alive_evidence, current_state: alive_evidence_state, eligibility: eligibility) }
    let(:american_indian_evidence)   { FactoryBot.create(:american_indian_evidence, current_state: american_indian_evidence_state, eligibility: eligibility) }
    let(:citizenship_evidence)   { FactoryBot.create(:citizenship_evidence, current_state: citizenship_evidence_state, eligibility: eligibility, due_on: Date.today + 5.days, verification_outstanding: true, is_satisfied: false) }
    let(:social_security_number_evidence)   { FactoryBot.create(:social_security_number_evidence, current_state: social_security_number_evidence_state, eligibility: eligibility) }

    context '#escalate_evidences_to_outstanding' do
      let(:alive_evidence_state) {:pending}
      let(:american_indian_evidence_state) {:outstanding}
      let(:citizenship_evidence_state) {:negative_response_received}
      let(:social_security_number_evidence_state) {:verified}
      before do
        alive_evidence
        american_indian_evidence
        citizenship_evidence
        social_security_number_evidence
        eligibility.escalate_evidences_to_outstanding("enrollment_purchase", "Coverage purchased for enrollment 12345")
      end

      it 'should update alive evidence to outstanding' do
        expect(alive_evidence.current_state).to eq(:outstanding)
        expect(alive_evidence.verification_histories.last.action).to eq("enrollment_purchase")
        expect(alive_evidence.verification_histories.last.update_reason).to eq("Coverage purchased for enrollment 12345")
      end

      it 'should not update american indian evidence' do
        expect(american_indian_evidence.current_state).to eq(:outstanding)
        expect(american_indian_evidence.verification_histories.last&.action).not_to eq("enrollment_purchase")
      end

      it 'should update citizenship evidence' do
        expect(citizenship_evidence.current_state).to eq(:outstanding)
        expect(citizenship_evidence.verification_histories.last.action).to eq("enrollment_purchase")
        expect(citizenship_evidence.verification_histories.last.update_reason).to eq("Coverage purchased for enrollment 12345")
      end

      it 'should not update social security number evidence' do
        expect(social_security_number_evidence.current_state).to eq(:verified)
      end

      it 'should call determine_eligibility_state after updating evidences' do
        expect(eligibility.current_state).to be_present
      end
    end

    context '#downgrade_evidences_to_nrr' do
      let(:alive_evidence_state) {:pending}
      let(:american_indian_evidence_state) {:outstanding}
      let(:citizenship_evidence_state) {:negative_response_received}
      let(:social_security_number_evidence_state) {:verified}
      before do
        alive_evidence
        american_indian_evidence
        citizenship_evidence
        social_security_number_evidence
        eligibility.downgrade_evidences_to_nrr("enrollment_purchase", "Coverage cancelled for enrollment 12345")
      end

      it 'should keep alive evidence as pending' do
        expect(alive_evidence.current_state).to eq(:pending)
      end

      it 'should waive american indian evidence to negative_response_received' do
        expect(american_indian_evidence.current_state).to eq(:negative_response_received)
        expect(american_indian_evidence.verification_histories.last.action).to eq("enrollment_purchase")
        expect(american_indian_evidence.verification_histories.last.update_reason).to eq("Coverage cancelled for enrollment 12345")
      end

      it 'should keep citizenship evidence as negative_response_received' do
        expect(citizenship_evidence.current_state).to eq(:negative_response_received)
      end

      it 'should not update social security number evidence' do
        expect(social_security_number_evidence.current_state).to eq(:verified)
      end

      it 'should call determine_eligibility_state after updating evidences' do
        expect(eligibility.current_state).to be_present
      end
    end
  end
end
