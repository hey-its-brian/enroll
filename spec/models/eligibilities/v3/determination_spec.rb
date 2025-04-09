# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Determination, type: :model do
  let(:applicant)   { FactoryBot.create(:individual_market_applicant) }
  let(:eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:determination) { FactoryBot.create(:v3_determination, eligibility: eligibility) }
  let(:basis)    { FactoryBot.create(:v3_basis, determination: determination) }

  before do
    basis
  end

  describe 'associations' do
    it 'is embedded in eligibility' do
      expect(determination.eligibility).to be_a(Eligibilities::V3::Eligibility)
    end

    it 'embeds many bases' do
      expect(determination.bases).to all(be_a(Eligibilities::V3::Basis))
    end
  end
end
