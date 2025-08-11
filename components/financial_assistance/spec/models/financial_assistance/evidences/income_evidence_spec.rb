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

  describe '#due_date_extended_at=' do
    let(:evidence) { FactoryBot.create(:income_evidence, :outstanding, due_date_extended_at: due_date_extended_at, eligibility: aptc_csr_eligibility) }

    context 'when due_date_extended_at is set' do
      let(:due_date_extended_at) { DateTime.now - 10.days }

      it 'raises a ReadonlyAttribute error when attempted to update the due_date_extended_at field' do
        expect(evidence.due_date_extended_at).to eq(due_date_extended_at)
        expect { evidence.due_date_extended_at = DateTime.now }.to raise_error(
          RuntimeError, 'due_date_extended_at is read-only and cannot be changed once set.'
        )
      end
    end

    context 'when due_date_extended_at is not set' do
      let(:due_date_extended_at) { nil }
      let(:current_time) { DateTime.now }

      it 'allows setting the due_date_extended_at field' do
        expect(evidence.due_date_extended_at).to be_nil
        expect { evidence.due_date_extended_at = current_time }.not_to raise_error
      end
    end
  end

  describe '#extend_due_date' do
    let(:evidence) do
      FactoryBot.create(
        :income_evidence,
        current_state: income_state,
        due_on: income_due_on,
        due_date_extended_at: income_due_date_extended_at,
        eligibility: aptc_csr_eligibility
      )
    end

    context 'when income evidence is not in outstanding/rejected status' do
      let(:income_state) { :verified }
      let(:income_due_on) { nil }
      let(:income_due_date_extended_at) { nil }

      it 'does not extend the due date' do
        evidence.auto_extend_due_date('test_action', 5, 'test_user')
        expect(evidence.reload.due_on).to be_nil
        expect(evidence.due_date_extended_at).to be_nil
        expect(evidence.verification_histories.count).to eq(0)
      end
    end
  end
end
