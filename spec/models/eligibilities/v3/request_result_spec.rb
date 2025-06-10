# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::RequestResult, type: :model do
  let(:applicant)       { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:evidence)        { FactoryBot.create(:alive_evidence, eligibility: ivl_eligibility) }
  let(:request_result)  { FactoryBot.create(:v3_request_result, evidence: evidence) }

  describe 'associations' do
    it 'is embedded in an evidence' do
      expect(request_result.evidence).to eq(evidence)
    end
  end

  describe 'fields' do
    it { should have_field(:result).of_type(String) }
    it { should have_field(:source).of_type(String) }
    it { should have_field(:source_transaction_id).of_type(String) }
    it { should have_field(:code).of_type(String) }
    it { should have_field(:code_description).of_type(String) }
    it { should have_field(:raw_payload).of_type(String) }
    it { should have_field(:date_of_action).of_type(DateTime) }
    it { should have_field(:action).of_type(String) }
  end

  describe 'callbacks' do
    it 'sets date_of_action before create' do
      expect(request_result.date_of_action).to be_present
    end
  end
end
