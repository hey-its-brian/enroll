# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Determination, type: :model do
  let(:applicant)   { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:determination) { FactoryBot.create(:v3_determination, eligibility: eligibility) }

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

  describe '#unique_basis_kinds' do
    it 'when there are duplicate basis kinds' do
      determination.bases << FactoryBot.build(:v3_basis, basis_kind: 'state_resident', determination: determination)
      determination.bases << FactoryBot.build(:v3_basis, basis_kind: 'state_resident', determination: determination)
      expect(determination).not_to be_valid
      expect(determination.errors[:bases]).to include('Duplicate basis kinds')
    end
  end

end