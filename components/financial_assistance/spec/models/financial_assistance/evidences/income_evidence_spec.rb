# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Evidences::IncomeEvidence, type: :model, dbclean: :after_each do
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

  describe '#retain_evidence_information' do
    let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
    let(:current_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, hbx_id: 'current_app_123') }
    let(:new_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, hbx_id: 'new_app_456') }

    let(:current_applicant) { FactoryBot.create(:financial_assistance_applicant, application: current_application) }
    let(:new_applicant) { FactoryBot.create(:financial_assistance_applicant, application: new_application) }

    let(:current_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: current_applicant) }
    let(:new_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: new_applicant) }

    let(:current_evidence) do
      FactoryBot.create(:income_evidence,
                        eligibility: current_eligibility,
                        current_state: current_state,
                        due_on: current_due_on,
                        due_date_extended_at: current_extended_at)
    end

    let(:new_evidence) do
      FactoryBot.create(:income_evidence,
                        eligibility: new_eligibility,
                        current_state: 'pending')
    end

    let(:current_state) { 'outstanding' }
    let(:current_due_on) { Date.current + 30.days }
    let(:current_extended_at) { nil }

    before do
      allow(new_evidence).to receive(:build_verification_history)
    end

    context 'when current evidence is in outstanding state' do
      let(:current_state) { 'outstanding' }

      it 'updates the state from current evidence' do
        expect { new_evidence.retain_evidence_information(current_evidence) }
          .to change { new_evidence.current_state }
          .from(:pending).to(:outstanding)
      end

      it 'copies the due date from current evidence' do
        expect { new_evidence.retain_evidence_information(current_evidence) }
          .to change { new_evidence.due_on }
          .from(nil).to(current_due_on)
      end

      it 'builds verification history with correct message' do
        new_evidence.retain_evidence_information(current_evidence)

        expected_message = "State updated from pending to outstanding " \
                          "and due date of #{current_due_on} copied " \
                          "from previous application current_app_123 application type faa " \
                          "due to annual eligibility redetermination."

        expect(new_evidence).to have_received(:build_verification_history)
          .with('retain_evidence_info_on_renewal', expected_message, 'system')
      end

      context 'when current evidence has extended due date' do
        let(:current_extended_at) { DateTime.current - 5.days }

        it 'copies the due date extended timestamp' do
          expect { new_evidence.retain_evidence_information(current_evidence) }
            .to change { new_evidence.due_date_extended_at }
            .from(nil).to(current_extended_at)
        end

        it 'builds verification history with extended due date message' do
          new_evidence.retain_evidence_information(current_evidence)

          expected_message = "State updated from pending to outstanding, " \
                            "due date of #{current_due_on} copied, " \
                            "and #{current_extended_at} automatic due date extended at copied " \
                            "from previous application current_app_123 application type faa " \
                            "due to annual eligibility redetermination."

          expect(new_evidence).to have_received(:build_verification_history)
            .with('retain_evidence_info_on_renewal', expected_message, 'system')
        end
      end

      context 'when current evidence has due date but not extended due date' do
        let(:current_extended_at) { nil }

        it 'builds verification history with due date message and not extended due date message' do
          new_evidence.retain_evidence_information(current_evidence)
          expected_message = "State updated from pending to outstanding " \
                                                         "and due date of #{current_due_on} copied " \
                                                         "from previous application current_app_123 application type faa " \
                                                         "due to annual eligibility redetermination."


          expect(new_evidence).to have_received(:build_verification_history)
            .with('retain_evidence_info_on_renewal', expected_message, 'system')
        end
      end

      context 'when current evidence does not have due date' do
        let(:current_due_on) { nil }

        it 'builds verification history with due date message and not extended due date message' do
          new_evidence.retain_evidence_information(current_evidence)
          expected_message = "State updated from pending to outstanding copied from previous application current_app_123 application type faa due to annual eligibility redetermination."

          expect(new_evidence).to have_received(:build_verification_history)
            .with('retain_evidence_info_on_renewal', expected_message, 'system')
        end
      end
    end

    context 'when current evidence is in rejected state' do
      let(:current_state) { 'rejected' }

      it 'copies the due date when in rejected state' do
        expect { new_evidence.retain_evidence_information(current_evidence) }
          .to change { new_evidence.due_on }
          .from(nil).to(current_due_on)
      end

      it 'builds verification history with due date message' do
        new_evidence.retain_evidence_information(current_evidence)

        expected_message = "State updated from pending to rejected " \
                          "and due date of #{current_due_on} copied " \
                          "from previous application current_app_123 application type faa " \
                          "due to annual eligibility redetermination."

        expect(new_evidence).to have_received(:build_verification_history)
          .with('retain_evidence_info_on_renewal', expected_message, 'system')
      end
    end

    context 'when current evidence is not in outstanding status' do
      let(:current_state) { 'verified' }

      it 'updates the state but does not copy due date' do
        new_evidence.retain_evidence_information(current_evidence)

        expect(new_evidence.current_state).to eq(:verified)
        expect(new_evidence.due_on).to be_nil
      end

      it 'builds verification history without due date information' do
        new_evidence.retain_evidence_information(current_evidence)

        expected_message = "State updated from pending to verified copied " \
                          "from previous application current_app_123 application type faa " \
                          "due to annual eligibility redetermination."

        expect(new_evidence).to have_received(:build_verification_history)
          .with('retain_evidence_info_on_renewal', expected_message, 'system')
      end
    end

    context 'when current evidence has no due date' do
      let(:current_due_on) { nil }
      let(:current_state) { 'outstanding' }

      it 'does not copy due date when current evidence has none' do
        new_evidence.retain_evidence_information(current_evidence)

        expect(new_evidence.due_on).to be_nil
      end

      it 'builds verification history without due date information' do
        new_evidence.retain_evidence_information(current_evidence)

        expected_message = "State updated from pending to outstanding copied " \
                          "from previous application current_app_123 application type faa " \
                          "due to annual eligibility redetermination."

        expect(new_evidence).to have_received(:build_verification_history)
          .with('retain_evidence_info_on_renewal', expected_message, 'system')
      end
    end

    context 'when current application is not a Financial Assistance application' do
      let(:individual_market_application) { FactoryBot.create(:individual_market_application, family_id: family.id) }
      let(:individual_market_applicant) { FactoryBot.create(:individual_market_applicant, application: individual_market_application) }
      let(:individual_market_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: individual_market_applicant) }
      let(:individual_market_evidence) do
        FactoryBot.create(:income_evidence,
                          eligibility: individual_market_eligibility,
                          current_state: 'outstanding')
      end

      it 'raises an error for non-FA applications' do
        expect { new_evidence.retain_evidence_information(individual_market_evidence) }
          .to raise_error(RuntimeError, 'Unexpected application type: qhp')
      end
    end

    context 'edge cases' do
      let(:current_state) { 'outstanding' }

      it 'handles same state transition' do
        new_evidence.update(current_state: 'outstanding')

        expect { new_evidence.retain_evidence_information(current_evidence) }
          .not_to change(new_evidence, :current_state)
      end

      it 'handles nil current state gracefully' do
        new_evidence.update(current_state: nil)

        expect { new_evidence.retain_evidence_information(current_evidence) }
          .to change(new_evidence, :current_state)
          .from(nil).to(:outstanding)
      end
    end
  end

  describe '#mark_as_verified' do
    let(:evidence) do
      FactoryBot.create(
        :income_evidence,
        eligibility: aptc_csr_eligibility,
        current_state: evidence_state,
        due_on: evidence_due_on,
        due_date_extended_at: evidence_due_date_extended_at
      )
    end

    context 'for valid evidence states that can be marked as verified' do
      shared_examples_for 'marks evidence as verified and resets due dates' do
        it 'marks the evidence as verified and resets the due_on & due_date_extended_at' do
          expect { evidence.mark_as_verified }.to change(evidence, :current_state).to(:verified)
          expect(evidence.due_on).to be_nil
          expect(evidence.due_date_extended_at).to be_nil
        end
      end

      %i[outstanding negative_response_received pending rejected review unverified].each do |state|
        context "when evidence is in #{state} state" do
          let(:evidence_state) { state }

          context 'with due date and extended timestamp' do
            let(:evidence_due_on) { 1.day.from_now }
            let(:evidence_due_date_extended_at) { Time.current }
            it_behaves_like 'marks evidence as verified and resets due dates'
          end

          context 'with due date only' do
            let(:evidence_due_on) { 1.day.from_now }
            let(:evidence_due_date_extended_at) { nil }
            it_behaves_like 'marks evidence as verified and resets due dates'
          end

          context 'without due date or extended timestamp' do
            let(:evidence_due_on) { nil }
            let(:evidence_due_date_extended_at) { nil }
            it_behaves_like 'marks evidence as verified and resets due dates'
          end
        end
      end
    end

    context 'for invalid evidence states that cannot be marked as verified' do
      shared_examples_for 'does not mark evidence as verified' do
        it 'does not mark the evidence as verified' do
          expect { evidence.mark_as_verified }.not_to change(evidence, :current_state)
        end
      end

      [:initial, :attested, :verified, :determined, :expired, :denied, :errored, :closed, :corrected].each do |state|
        context "when evidence is in #{state} state" do
          let(:evidence_state) { state }
          let(:evidence_due_on) { nil }
          let(:evidence_due_date_extended_at) { nil }

          it_behaves_like 'does not mark evidence as verified'
        end
      end
    end
  end
end
