# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/shared_contexts/valid_cv3_application_setup.rb')

RSpec.describe ::Operations::FinancialAssistance::ExtendEvidenceDueOn, type: :model, dbclean: :after_each do
  include_context "valid cv3 application setup"

  context 'valid arguments for one applicant' do
    let(:extension_days) { 30 }

    context "for one evidence type" do
      let(:applicant_income_evidence_due_on) {applicant.income_evidence.due_on}

      before do
        application.update_attributes!(aasm_state: 'determined')
        applicant.income_evidence.update_attributes!(due_on: TimeKeeper.date_of_record - 1.day, aasm_state: 'outstanding')
        applicant_income_evidence_due_on
      end

      it 'should return a success object' do
        result = subject.call({evidence: applicant.income_evidence, extension_days: extension_days})
        expect(result).to be_a(Dry::Monads::Result::Success)
        applicant.income_evidence.reload
        expect(applicant.income_evidence.due_on).to eq(TimeKeeper.date_of_record + extension_days.days)
      end
    end
  end

  context 'valid arguments for multiple applicants' do
    let(:dependent) { FactoryBot.create(:person, :with_consumer_role, hbx_id: '100096', first_name: "dep") }
    let!(:family_member) { FactoryBot.create(:family_member, family: family, person: dependent) }

    let(:applicant2) do
      FactoryBot.create(
        :financial_assistance_applicant,
        :with_student_information,
        :with_home_address,
        application: application,
        is_primary_applicant: false,
        ssn: '889888488',
        dob: Date.new(1996,11,17),
        first_name: dependent.first_name,
        last_name: dependent.last_name,
        gender: dependent.gender,
        person_hbx_id: dependent.hbx_id,
        eligibility_determination_id: eligibility_determination.id,
        has_enrolled_health_coverage: has_enrolled_health_coverage,
        benchmark_premiums: {
          health_only_lcsp_premiums: [{ member_identifier: dependent.hbx_id, monthly_premium: 90.0 }, { member_identifier: person.hbx_id, monthly_premium: 90.0 }],
          health_only_slcsp_premiums: [{ member_identifier: dependent.hbx_id, monthly_premium: 100.0 }, { member_identifier: person.hbx_id, monthly_premium: 100.0 }]
        }
      )
    end

    context "for one evidence type" do
      let!(:applicant2_income_evidence) do
        applicant2.create_income_evidence(
          key: :income,
          title: 'Income',
          aasm_state: :pending,
          due_on: TimeKeeper.date_of_record,
          verification_outstanding: true,
          is_satisfied: false
        )
      end

      let(:extension_days) { 30 }
      let(:applicant_income_evidence_due_on) {applicant.income_evidence.due_on}
      let(:applicant2_income_evidence_due_on) {applicant2.income_evidence.due_on}

      before do
        application.update_attributes!(aasm_state: 'determined')
        applicant.income_evidence.update_attributes!(due_on: TimeKeeper.date_of_record - 1.day, aasm_state: 'outstanding')
        applicant2.income_evidence.update_attributes!(due_on: TimeKeeper.date_of_record, aasm_state: 'outstanding')
        applicant_income_evidence_due_on
        applicant2_income_evidence_due_on
        @result1 = subject.call({evidence: applicant.income_evidence, extension_days: extension_days})
        @result2 = subject.call({evidence: applicant2.income_evidence, extension_days: extension_days})
      end

      it 'should return a success object' do
        expect(@result1).to be_a(Dry::Monads::Result::Success)
        expect(@result2).to be_a(Dry::Monads::Result::Success)
      end

      it 'should update the evidence due date' do
        applicant.income_evidence.reload
        applicant2.income_evidence.reload
        expect(applicant.income_evidence.due_on).to eq(TimeKeeper.date_of_record + extension_days.days)
        expect(applicant2.income_evidence.due_on).to eq(TimeKeeper.date_of_record + extension_days.days)
      end
    end

    context "when verification history date of action is before aasm state transition" do
      let!(:applicant2_income_evidence) do
        applicant2.create_income_evidence(
          key: :income,
          title: 'Income',
          aasm_state: :pending,
          due_on: TimeKeeper.date_of_record,
          verification_outstanding: true,
          is_satisfied: false
        )
      end

      let(:extension_days) { 30 }
      let(:applicant2_income_evidence_due_on) {applicant2.income_evidence.due_on}
      let!(:verification_history) { applicant2_income_evidence.verification_histories.create(action: "auto_extend_due_date", date_of_action: TimeKeeper.date_of_record - 2.days, modifier: "Admin") }

      let!(:workflow_state_transition) do
        applicant2_income_evidence.workflow_state_transitions.create(
          to_state: "verified",
          from_state: "pending",
          transition_at: TimeKeeper.date_of_record - 1.day,
          user_id: "Admin",
          reason: "Admin"
        )
      end

      before do
        application.update_attributes!(aasm_state: 'determined')
        applicant2.income_evidence.update_attributes!(due_on: TimeKeeper.date_of_record - 1.day, aasm_state: 'outstanding')
        applicant2_income_evidence_due_on
        @result2 = subject.call({evidence: applicant2.income_evidence, extension_days: extension_days})
      end

      it 'extends the due date' do
        expect(@result2).to be_a(Dry::Monads::Result::Success)
        applicant2.income_evidence.reload
        expect(applicant2.income_evidence.due_on).to eq(TimeKeeper.date_of_record + extension_days.days)
      end
    end

    context "for due date greater than today" do
      let!(:applicant2_income_evidence) do
        applicant2.create_income_evidence(
          key: :income,
          title: 'Income',
          aasm_state: :pending,
          due_on: TimeKeeper.date_of_record,
          verification_outstanding: true,
          is_satisfied: false
        )
      end

      let(:extension_days) { 30 }
      let(:applicant_income_evidence_due_on) {applicant.income_evidence.due_on}
      let(:applicant2_income_evidence_due_on) {applicant2.income_evidence.due_on}

      before do
        application.update_attributes!(aasm_state: 'determined')
        applicant.income_evidence.update_attributes!(due_on: TimeKeeper.date_of_record - 1.day, aasm_state: 'outstanding')
        applicant2.income_evidence.update_attributes!(due_on: TimeKeeper.date_of_record + 1.day, aasm_state: 'outstanding')
        applicant_income_evidence_due_on
        applicant2_income_evidence_due_on
        @result1 = subject.call({evidence: applicant.income_evidence, extension_days: extension_days})
        @result2 = subject.call({evidence: applicant2.income_evidence, extension_days: extension_days})
      end

      it 'should return status' do
        expect(@result1).to be_a(Dry::Monads::Result::Success)
        expect(@result2).to be_a(Dry::Monads::Result::Failure)
        expect(@result2.failure).to eq("evidence due date is blank or greater than today")
      end

      it 'should update the evidence due date' do
        applicant.income_evidence.reload
        expect(applicant.income_evidence.due_on).to eq(TimeKeeper.date_of_record + extension_days.days)
      end

      it 'should not update the evidence due date' do
        applicant2.income_evidence.reload
        expect(applicant2.income_evidence.due_on).to eq(TimeKeeper.date_of_record + 1.day)
      end
    end
  end
end