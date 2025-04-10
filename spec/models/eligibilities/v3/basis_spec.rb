# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Basis, type: :model do
  let(:applicant)   { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:determination) { FactoryBot.create(:v3_determination, eligibility: eligibility) }
  let(:basis) { FactoryBot.create(:v3_basis, determination: determination) }

  it 'has the expected fields' do
    expect(basis).to have_field(:basis_kind).of_type(String)
    expect(basis).to have_field(:is_satisfied).of_type(Mongoid::Boolean)
  end

  it 'embeds in determination' do
    expect(basis.determination).to be_a(Eligibilities::V3::Determination)
    expect(basis.determination).to eq(determination)
  end
end
