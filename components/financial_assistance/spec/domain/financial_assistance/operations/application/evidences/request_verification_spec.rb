# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Operations::Application::Evidences::RequestVerification, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  let(:person_1) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:person_2) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:person_3) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person_1)}
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'determined', hbx_id: "830293", effective_date: TimeKeeper.date_of_record.beginning_of_year) }
  let(:eligibility_determination) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }

  let(:applicant_1) do
    FactoryBot.build(:financial_assistance_applicant,
                     :with_student_information,
                     :with_home_address,
                     application: application,
                     is_primary_applicant: true,
                     ssn: '889984400',
                     dob: Date.new(1994,11,17),
                     first_name: person_1.first_name,
                     last_name: person_1.last_name,
                     gender: person_1.gender,
                     person_hbx_id: person_1.hbx_id,
                     eligibility_determination_id: eligibility_determination.id)
  end

  let(:applicant_2) do
    FactoryBot.build(:financial_assistance_applicant,
                     :with_student_information,
                     :with_home_address,
                     :with_income_evidence,
                     application: application,
                     is_primary_applicant: false,
                     ssn: '889984400',
                     dob: Date.new(1995,11,17),
                     first_name: person_2.first_name,
                     last_name: person_2.last_name,
                     gender: person_2.gender,
                     person_hbx_id: person_2.hbx_id,
                     eligibility_determination_id: eligibility_determination.id)
  end

  let(:applicant_3) do
    FactoryBot.build(:financial_assistance_applicant,
                     :with_student_information,
                     :with_home_address,
                     :with_income_evidence,
                     application: application,
                     is_primary_applicant: false,
                     is_ia_eligible: false,
                     ssn: '889984400',
                     dob: Date.new(2007,11,17),
                     first_name: person_3.first_name,
                     last_name: person_3.last_name,
                     gender: person_3.gender,
                     person_hbx_id: person_3.hbx_id,
                     eligibility_determination_id: eligibility_determination.id)
  end

  let(:create_home_address) do
    add = ::FinancialAssistance::Locations::Address.new({
                                                          kind: 'home',
                                                          address_1: '3 Awesome Street',
                                                          address_2: '#300',
                                                          city: 'Washington',
                                                          state: 'DC',
                                                          zip: '20001'
                                                        })
    applicant_1.addresses << add
    applicant_1.save!
  end

  let(:hbx_profile) {FactoryBot.create(:hbx_profile)}
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }

  let(:event) { Success(double) }

  let(:benchmark_premiums) do
    {
      health_only_lcsp_premiums: [
        { member_identifier: applicant_1.person_hbx_id, monthly_premium: 90.0 },
        { member_identifier: applicant_2.person_hbx_id, monthly_premium: 91.0 },
        { member_identifier: applicant_3.person_hbx_id, monthly_premium: 92.0 }
      ],
      health_only_slcsp_premiums: [
        { member_identifier: applicant_1.person_hbx_id, monthly_premium: 100.00 },
        { member_identifier: applicant_2.person_hbx_id, monthly_premium: 101.00 },
        { member_identifier: applicant_3.person_hbx_id, monthly_premium: 102.00 }
      ]
    }
  end

  let(:update_benchmark_premiums) do
    application.applicants.each { |applicant| applicant.benchmark_premiums = benchmark_premiums }
    application.save!
  end

  before do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    create_home_address
    update_benchmark_premiums
    application.applicants.each do |applicant|
      aptc_csr_eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant)
      old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
      new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
      aptc_csr_eligibility.state_histories << old_state
      aptc_csr_eligibility.state_histories << new_state
      aptc_csr_eligibility.save!
      FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence', key: :income_evidence, current_state: 'pending')
      FactoryBot.create(:esi_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::EsiMecEvidence', key: :esi_mec_evidence, title: 'Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                           description: 'EsiMecEvidence', current_state: "pending")
      FactoryBot.create(:non_esi_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::NonEsiMecEvidence', key: :non_esi_mec_evidence, title: 'Non Esi MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                               description: 'NonEsiMecEvidence', current_state: "pending")
      FactoryBot.create(:local_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::LocalMecEvidence', key: :local_mec_evidence, title: 'Local MEC Evidence', determined_at: TimeKeeper.date_of_record,
                                             description: 'LocalMecEvidence', current_state: "pending")
    end

    allow(subject).to receive(:build_event).and_return(event)
    allow(subject).to receive(:publish_event_result).and_return(Success("Event published successfully"))

    allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
    allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
    allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
    application.reload
    # aptc_csr_eligibility1 = applicant_1.aptc_csr_eligibility
    # aptc_csr_eligibility2 = applicant_2.aptc_csr_eligibility
    # aptc_csr_eligibility3 = applicant_3.aptc_csr_eligibility
    # aptc_csr_eligibility1.income_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility2.income_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility3.income_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility1.esi_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility2.esi_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility3.esi_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility1.non_esi_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility2.non_esi_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility3.non_esi_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility1.local_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility2.local_mec_evidence.update(current_state: 'pending')
    # aptc_csr_eligibility3.local_mec_evidence.update(current_state: 'pending')

    update_benchmark_premiums
  end

  let(:payload_entity) { ::Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application).value! }

  context 'with valid application' do
    before do
      @result = subject.call({application: application, payload_entity: payload_entity})
    end

    it 'should return success' do
      expect(@result).to be_success
    end

    it 'should return success with message' do
      expect(@result.success).to eq('Event published successfully')
    end

    it 'should add verification histories to all evidences' do
      application.applicants.each do |applicant|
        eligibility = applicant.aptc_csr_eligibility
        eligibility.evidences.each do |evidence|
          expect(evidence.verification_histories.length).to eq 1
          expect(evidence.verification_histories.last.action).to eq 'application_determined'
          expect(evidence.verification_histories.last.update_reason).to eq 'Requested Hub for verification'
          expect(evidence.verification_histories.last.updated_by).to eq 'system'
        end
      end
    end
  end

  context 'eligibility validation' do

    context 'with an invalid applicant' do
      context 'on mec evidence' do
        before do
          applicant_1.update(ssn: '000348745')
          application.reload
          @result = subject.call({application: application, payload_entity: payload_entity})
          application.reload
          @applicant_1 = application.applicants[0]
          @applicant_2 = application.applicants[1]
          @applicant_3 = application.applicants[2]
        end

        it 'should be successful' do
          expect(@result).to be_success
        end

        it "should update invalid applicants' verification history with additional error history" do
          evidence = @applicant_1.aptc_csr_eligibility.esi_mec_evidence
          expect(evidence.verification_histories.length).to eq 2
          expect(evidence.verification_histories.last.update_reason).to include 'Invalid SSN'
        end

        it "should NOT add an error to valid applicants' verification histories" do
          evidence_2 = @applicant_2.aptc_csr_eligibility.esi_mec_evidence
          evidence_3 = @applicant_3.aptc_csr_eligibility.esi_mec_evidence
          expect(evidence_2.verification_histories.length).to eq 1
          expect(evidence_3.verification_histories.length).to eq 1
        end

        it 'should not affect the valid applicants evidence current_states' do
          evidence_2 = @applicant_2.aptc_csr_eligibility.esi_mec_evidence
          evidence_3 = @applicant_3.aptc_csr_eligibility.esi_mec_evidence

          expect(evidence_2.current_state).to eq :pending
          expect(evidence_3.current_state).to eq :pending
        end

        it 'should update the invalid applicants current_states to attested' do
          evidence = @applicant_1.aptc_csr_eligibility.esi_mec_evidence
          expect(evidence.current_state).to eq :attested
        end
      end

      context 'on income evidence' do
        before do
          applicant_1.update(ssn: '000348745')
          application.reload
          @result = subject.call({application: application, payload_entity: payload_entity})
          application.reload
          applicant_1 = application.applicants[0]
          applicant_2 = application.applicants[1]
          applicant_3 = application.applicants[2]
          @evidence_1 = applicant_1.aptc_csr_eligibility.income_evidence
          @evidence_2 = applicant_2.aptc_csr_eligibility.income_evidence
          @evidence_3 = applicant_3.aptc_csr_eligibility.income_evidence
        end

        it 'should succeed' do
          expect(@result).to be_success
        end

        it "should update all applicants' verification histories" do
          expect(@evidence_1.verification_histories.length).to eq 2
          expect(@evidence_2.verification_histories.length).to eq 2
          expect(@evidence_3.verification_histories.length).to eq 2
        end

        it 'should update the current_states to negative_response_received' do
          expect(@evidence_1.current_state).to eq :negative_response_received
          expect(@evidence_2.current_state).to eq :negative_response_received
          expect(@evidence_3.current_state).to eq :negative_response_received
        end
      end
    end

    context 'with ALL invalid applicants' do
      before do
        applicant_1.update(ssn: '000348745')
        applicant_2.update(ssn: '000348746')
        applicant_3.update(ssn: '000348747')
        application.reload
        @result = subject.call({application: application, payload_entity: payload_entity})
      end

      it 'should record failure and return success' do
        expect(@result).to be_success
      end
    end
  end
end