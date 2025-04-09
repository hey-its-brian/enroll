# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Evidences::IncomeEvidence, type: :model do
  let(:person)                { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family)                { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application)           { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
  let(:applicant)             { FactoryBot.create(:financial_assistance_applicant, application: application) }
  let(:aptc_csr_eligibility)  { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:evidence)              { FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility) }

  describe 'inheritance and modules' do
    it 'inherits from Evidence base class and includes EvidenceUtils' do
      expect(described_class.superclass).to eq(::Eligibilities::V3::Evidence)
      expect(described_class.included_modules).to include(::Eligibilities::V3::EvidenceUtils)
    end
  end

  describe '#latest_state_history' do
    let(:old_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 2.days.ago) }
    let(:new_state_history) { FactoryBot.create(:v3_state_history, status_trackable: evidence, created_at: 1.day.ago) }

    before do
      old_state_history
      new_state_history
    end

    it 'returns the most recent state history and memoizes the result' do
      expect(evidence.latest_state_history).to eq(new_state_history)

      result = evidence.latest_state_history
      expect(evidence.state_histories).not_to receive(:newest)
      expect(evidence.latest_state_history).to eq(result)
    end
  end
end
