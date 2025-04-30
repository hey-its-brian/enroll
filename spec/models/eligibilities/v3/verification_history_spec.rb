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
end
