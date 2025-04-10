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
end
