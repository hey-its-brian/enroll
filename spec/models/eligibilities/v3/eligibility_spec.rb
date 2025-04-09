# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Eligibility, type: :model do
  let(:applicant) { FactoryBot.create(:individual_market_applicant) }
  let(:eligibility) { FactoryBot.create(:v3_eligibility, :individual_market_eligibility, eligible: applicant) }

  describe 'Mongoid attributes' do
    it { is_expected.to be_mongoid_document }
    it { is_expected.to have_timestamps }
  end

  describe 'fields' do
    it { is_expected.to have_field(:key).of_type(Symbol) }
    it { is_expected.to have_field(:title).of_type(String) }
    it { is_expected.to have_field(:description).of_type(String) }
    it { is_expected.to have_field(:current_state).of_type(Symbol).with_default_value_of(:initial) }
    it { is_expected.to have_field(:is_satisfied).of_type(Mongoid::Boolean).with_default_value_of(false) }
    it { is_expected.to have_field(:determined_at).of_type(DateTime) }
    it { is_expected.to have_field(:is_disqualified).of_type(Mongoid::Boolean).with_default_value_of(false) }
    it { is_expected.to have_field(:disqualified_at).of_type(DateTime) }
    it { is_expected.to have_field(:disqualified_reason).of_type(String) }
  end

  describe 'associations' do
    it { is_expected.to be_embedded_in(:eligible) }
    it { is_expected.to embed_many(:determinations).of_type(Eligibilities::V3::Determination) }
    it { is_expected.to embed_many(:evidences).of_type(Eligibilities::V3::Evidence) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_uniqueness_of(:key) }
  end

  describe 'constants' do
    it 'defines EVIDENCES constant as a frozen array' do
      expect(described_class::EVIDENCES).to eq([])
      expect(described_class::EVIDENCES).to be_frozen
    end
  end

  describe 'scopes' do
    describe '.by_key' do
      it 'returns eligibilities with the specified key' do
        eligibility
        expect(applicant.eligibilities.by_key(:individual_market_eligibility).to_a).to include(eligibility)
      end
    end

    describe '.eligible' do
      it 'returns eligibilities with current_state set to eligible' do
        eligible_eligibility = FactoryBot.create(:v3_eligibility, :magi_medicaid_eligibility, current_state: :eligible, eligible: applicant)
        ineligible_eligibility = FactoryBot.create(:v3_eligibility, :aptc_csr_eligibility, current_state: :ineligible, eligible: applicant)

        expect(applicant.eligibilities.eligible.to_a).to include(eligible_eligibility)
        expect(applicant.eligibilities.eligible.to_a).not_to include(ineligible_eligibility)
      end
    end

    describe '.ineligible' do
      it 'returns eligibilities with current_state set to ineligible' do
        eligible_eligibility = FactoryBot.create(:v3_eligibility, :magi_medicaid_eligibility, current_state: :eligible, eligible: applicant)
        ineligible_eligibility = FactoryBot.create(:v3_eligibility, :aptc_csr_eligibility, current_state: :ineligible, eligible: applicant)

        expect(applicant.eligibilities.ineligible.to_a).to include(ineligible_eligibility)
        expect(applicant.eligibilities.ineligible.to_a).not_to include(eligible_eligibility)
      end
    end

    describe '.disqualified' do
      it 'returns eligibilities flagged as disqualified' do
        disqualified = FactoryBot.create(:v3_eligibility, :magi_medicaid_eligibility, :disqualified, eligible: applicant)
        not_disqualified = FactoryBot.create(:v3_eligibility, :aptc_csr_eligibility, eligible: applicant)

        expect(applicant.eligibilities.disqualified.to_a).to include(disqualified)
        expect(applicant.eligibilities.disqualified.to_a).not_to include(not_disqualified)
      end
    end
  end
end
