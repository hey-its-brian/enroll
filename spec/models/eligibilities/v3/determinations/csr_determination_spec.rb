# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Determinations::CsrDetermination, type: :model do
  let(:applicant)   { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:determination) { FactoryBot.create(:csr_determination, :with_basis, :with_csr_limited, eligibility: eligibility) }

  describe 'associations' do
    it 'is embedded in eligibility' do
      expect(determination.eligibility).to be_a(Eligibilities::V3::Eligibility)
    end

    it 'embeds many bases' do
      expect(determination.bases).to all(be_a(Eligibilities::V3::Basis))
    end
  end

  describe 'validations' do
    it { should validate_presence_of(:is_eligible) }
    it 'should be valid' do
      expect(determination).to be_valid
    end
  end

  describe '#determine_individual_market_eligibility' do
    context 'when all bases are present and satisfied' do
      it 'sets is_eligible to true' do
        determination.bases.first.update(is_satisfied: true)
        determination.determine_individual_market_eligibility
        expect(determination.is_eligible).to be true
      end
    end

    context 'when basis missing' do
      it 'sets is_eligible to false' do
        determination.bases.first.destroy
        determination.determine_individual_market_eligibility
        expect(determination.is_eligible).to be false
      end
    end

    context 'when csr_type is not csr_limited' do
      it 'sets is_eligible to false' do
        determination.update(csr_type: "csr_100")
        determination.determine_individual_market_eligibility
        expect(determination.is_eligible).to be false
      end
    end

    context 'when any basis is not satisfied' do
      it 'sets is_eligible to false' do
        determination.bases.first.update(is_satisfied: false)
        determination.determine_individual_market_eligibility
        expect(determination.is_eligible).to be false
      end
    end
  end

  describe '#unique_basis_kinds' do
    it 'when there are duplicate basis kinds' do
      determination.bases << build(:v3_basis, basis_kind: 'ai_an_attested', determination: determination)
      expect(determination).not_to be_valid
      expect(determination.errors[:bases]).to include('Duplicate basis kinds')
    end
  end

  describe '#bases_must_be_valid_basis_kinds' do
    it 'when there is an invalid basis kind' do
      determination.bases.first.update(basis_kind: 'invalid_basis_kind')
      expect(determination).not_to be_valid
      expect(determination.errors[:bases]).to include('Invalid basis kind: invalid_basis_kind')
    end
  end
end
