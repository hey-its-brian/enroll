# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('spec/shared_contexts/valid_cv3_application_setup.rb')

RSpec.describe ::Operations::FinancialAssistance::BulkHubCallsForEvidences, type: :model, dbclean: :after_each do
  include_context "valid cv3 application setup"

  let!(:esi_evidence) do
    applicant.esi_evidence = FactoryBot.build(:evidence, :with_request_results, :with_verification_histories, key: :esi_mec, title: 'ESI MEC', aasm_state: esi_evidence_aasm_state, is_satisfied: false)
    applicant.save!
    applicant.esi_evidence
  end

  let!(:non_esi_evidence) do
    applicant.non_esi_evidence = FactoryBot.build(:evidence, :with_request_results, :with_verification_histories, key: :non_esi_mec, title: 'Non ESI MEC', aasm_state: non_esi_evidence_aasm_state, is_satisfied: false)
    applicant.save!
    applicant.non_esi_evidence
  end

  let!(:local_mec_evidence) do
    applicant.local_mec_evidence = FactoryBot.build(:evidence, :with_request_results, :with_verification_histories, key: :local_mec, title: 'Local MEC', aasm_state: local_mec_evidence_aasm_state, is_satisfied: false)
    applicant.save!
    applicant.local_mec_evidence
  end

  let(:esi_evidence_aasm_state) { 'pending' }
  let(:non_esi_evidence_aasm_state) { 'pending' }
  let(:local_mec_evidence_aasm_state) { 'pending' }

  context 'invalid arguments' do
    before do
      @result = subject.call({hbx_ids: ['12345'], evidence_types: ['income_evidence']})
    end

    it 'should return a failure object' do
      expect(@result).to be_a(Dry::Monads::Result::Failure)
      expect(@result.failure).to eq('Currently this feature is only enabled for esi and local MEC evidences')
    end
  end

  context 'valid arguments' do
    let(:esi_evidence_aasm_state) { 'outstanding' }
    let(:non_esi_evidence_aasm_state) { 'outstanding' }
    let(:local_mec_evidence_aasm_state) { 'outstanding' }

    context "for one evidence type" do
      before do
        application.update_attributes!(aasm_state: 'determined')

        @result = subject.call({hbx_ids: [person.hbx_id], evidence_types: ["esi_evidence"]})
      end

      it 'should return a success object' do
        expect(@result).to be_a(Dry::Monads::Result::Success)
      end

      it 'should create a csv file' do
        expect(File.exist?("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")).to be_truthy
      end

      it 'should have the correct data in the csv file' do
        csv_data = CSV.read("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv", headers: true)
        expect(csv_data.size).to eq(1)
        expect(csv_data[0]["Person HBX ID"]).to eq(person.hbx_id)
        expect(csv_data[0]["Status"]).to eq("Hub call initiated for esi_mec")
      end
    end

    context "for two evidence type" do
      before do
        application.update_attributes!(aasm_state: 'determined')

        @result = subject.call({hbx_ids: [person.hbx_id], evidence_types: ["esi_evidence", "local_mec_evidence"]})
      end

      it 'should return a success object' do
        expect(@result).to be_a(Dry::Monads::Result::Success)
      end

      it 'should create a csv file' do
        expect(File.exist?("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")).to be_truthy
      end

      it 'should have the correct data in the csv file' do
        csv_data = CSV.read("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv", headers: true)
        expect(csv_data.size).to eq(2)
        expect(csv_data[0]["Person HBX ID"]).to eq(person.hbx_id)
        expect(csv_data[0]["Status"]).to eq("Hub call initiated for esi_mec")
        expect(csv_data[1]["Person HBX ID"]).to eq(person.hbx_id)
        expect(csv_data[1]["Status"]).to eq("Hub call initiated for local_mec")
      end
    end

    context 'for a person having another, older application which is submitted more recently' do
      let(:more_recent_hbx_id) { (application.hbx_id.to_i + 1).to_s }
      let!(:more_recent_application) do
        FactoryBot.create(
          :financial_assistance_application,
          hbx_id: more_recent_hbx_id,
          family_id: application.family.id,
          assistance_year: application.assistance_year,
          created_at: application.created_at - 1.day,
          submitted_at: application.submitted_at + 1.day
        )
      end

      it "should process the more recently submitted application" do
        result = subject.call({hbx_ids: [person.hbx_id], evidence_types: ["esi_evidence"]})
        expect(result).to be_a(Dry::Monads::Result::Success)
        csv_data = CSV.read("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
        expect(csv_data[1][0]).to eq(more_recent_hbx_id)
      end
    end
  end

  context "person not found" do
    before do
      @result = subject.call({hbx_ids: ["12345"], evidence_types: ["esi_evidence"]})
    end

    it 'should return a success object' do
      expect(@result).to be_a(Dry::Monads::Result::Success)

    end
    it 'should create a csv file' do
      expect(File.exist?("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")).to be_truthy
    end

    it 'should have fail cases in the csv file' do
      csv_data = CSV.read("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv", headers: true)
      expect(csv_data.size).to eq(1)
      expect(csv_data[0]["Person HBX ID"]).to eq("12345")
      expect(csv_data[0]["Status"]).to eq("Person not found")
    end
  end

  context "family not found" do
    let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }

    before do
      @result = subject.call({hbx_ids: [person2.hbx_id], evidence_types: ["esi_evidence"]})
    end

    it 'should return a success object' do
      expect(@result).to be_a(Dry::Monads::Result::Success)

    end
    it 'should create a csv file' do
      expect(File.exist?("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")).to be_truthy
    end

    it 'should have failed cases in the csv file' do
      csv_data = CSV.read("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv", headers: true)
      expect(csv_data.size).to eq(1)
      expect(csv_data[0]["Person HBX ID"]).to eq(person2.hbx_id)
      expect(csv_data[0]["Status"]).to eq("Families not found")
    end
  end

  context "application not found" do
    let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let!(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }

    before do
      @result = subject.call({hbx_ids: [person2.hbx_id], evidence_types: ["esi_evidence"]})
    end

    it 'should return a success object' do
      expect(@result).to be_a(Dry::Monads::Result::Success)

    end
    it 'should create a csv file' do
      expect(File.exist?("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")).to be_truthy
    end

    it 'should have failed cases in the csv file' do
      csv_data = CSV.read("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv", headers: true)
      expect(csv_data.size).to eq(1)
      expect(csv_data[0]["Person HBX ID"]).to eq(person2.hbx_id)
      expect(csv_data[0]["Status"]).to eq("Determined application not found")
    end
  end

  after :all do
    File.delete("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv") if File.exist?("#{Rails.root}/bulk_evidences_hub_call_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv")
  end
end