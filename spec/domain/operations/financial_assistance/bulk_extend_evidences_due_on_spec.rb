# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/shared_contexts/valid_cv3_application_setup.rb')

RSpec.describe ::Operations::FinancialAssistance::BulkExtendEvidencesDueOn, type: :model, dbclean: :after_each do
  include_context "valid cv3 application setup"

  context 'valid arguments for one applicant' do
    let(:extension_days) { 30 }

    context "for one evidence type" do
      let(:applicant_income_evidence_due_on) {applicant.income_evidence.due_on}

      before do
        application.update_attributes!(aasm_state: 'determined')
        applicant.income_evidence.update_attributes!(due_on: TimeKeeper.date_of_record - 1.day, aasm_state: 'outstanding')
        applicant_income_evidence_due_on
        @result = subject.call({application_hash: {"#{application.hbx_id}": [applicant.person_hbx_id]}, evidence_types: ["income_evidence"], extension_days: extension_days})
      end

      it 'should return a success object' do
        expect(@result).to be_a(Dry::Monads::Result::Success)
      end

      it 'should create a csv file' do
        expect(File.exist?("#{Rails.root}/bulk_extend_evidence_due_on_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")).to be_truthy
      end

      it 'should have the correct data in the csv file' do
        applicant.income_evidence.reload
        csv_data = CSV.read("#{Rails.root}/bulk_extend_evidence_due_on_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv", headers: true)
        expect(csv_data.size).to eq(1)
        expect(csv_data[0]["Applicant Person HBX ID"]).to eq(person.hbx_id)
        expect(csv_data[0]["Status"]).to eq("#{applicant.income_evidence.key} due date extended from #{applicant_income_evidence_due_on.strftime('%m/%d/%Y')} to #{applicant.income_evidence.due_on.strftime('%m/%d/%Y')}")
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
        @result = subject.call({application_hash: {"#{application.hbx_id}": [applicant.person_hbx_id, applicant2.person_hbx_id]}, evidence_types: ["income_evidence"], extension_days: extension_days})
      end

      it 'should return a success object' do
        expect(@result).to be_a(Dry::Monads::Result::Success)
      end

      it 'should create a csv file' do
        expect(File.exist?("#{Rails.root}/bulk_extend_evidence_due_on_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")).to be_truthy
      end

      it 'should have the correct data in the csv file' do
        applicant.income_evidence.reload
        applicant2.income_evidence.reload
        csv_data = CSV.read("#{Rails.root}/bulk_extend_evidence_due_on_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv", headers: true)
        expect(csv_data.size).to eq(2)
        expect(csv_data[0]["Applicant Person HBX ID"]).to eq(person.hbx_id)
        expect(csv_data[0]["Status"]).to eq("#{applicant.income_evidence.key} due date extended from #{applicant_income_evidence_due_on.strftime('%m/%d/%Y')} to #{applicant.income_evidence.due_on.strftime('%m/%d/%Y')}")
        expect(csv_data[1]["Applicant Person HBX ID"]).to eq(dependent.hbx_id)
        expect(csv_data[1]["Status"]).to eq("#{applicant2.income_evidence.key} due date extended from #{applicant2_income_evidence_due_on.strftime('%m/%d/%Y')} to #{applicant2.income_evidence.due_on.strftime('%m/%d/%Y')}")
      end
    end
  end
end