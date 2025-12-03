# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Operations::Applications::Rrv::IncomeEvidence::RequestVerification, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  let(:person_1) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:person_2) { FactoryBot.create(:person, :with_ssn, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person_1)}
  let!(:system_date) { Date.today }
  let!(:application2) do
    result = FactoryBot.create(:financial_assistance_application, hbx_id: '300000126', aasm_state: "determined", family_id: family.id, submitted_at: DateTime.new(system_date.year, system_date.month, system_date.day) - 30.minutes)
    member = FactoryBot.create(:financial_assistance_applicant,
                               eligibility_determination_id: nil,
                               person_hbx_id: person_1.hbx_id,
                               is_primary_applicant: true,
                               first_name: 'esi',
                               last_name: 'evidence',
                               ssn: "889984400",
                               dob: Date.new(1994,11,17),
                               family_member_id: family.primary_family_member.id,
                               application: result)
    member.build_aptc_eligibilities_evidences
    member.build_ivl_eligibility_with_evidences
    member.save!
    family.assign_latest_application_gid
    family.save!
    ::Operations::Eligibilities::BuildFamilyDetermination.new.call({family: family})

    result
  end

  let(:application) do
    FactoryBot.create(:financial_assistance_application, family_id: family.id, aasm_state: 'determined', hbx_id: "830293", effective_date: TimeKeeper.date_of_record.beginning_of_year,
                                                         submitted_at: DateTime.new(system_date.year, system_date.month, system_date.day))
  end
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
                     ssn: '889984401',
                     dob: Date.new(1996,11,17),
                     first_name: person_2.first_name,
                     last_name: person_2.last_name,
                     gender: person_2.gender,
                     person_hbx_id: person_2.hbx_id,
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
        { member_identifier: applicant_2.person_hbx_id, monthly_premium: 91.0 }
      ],
      health_only_slcsp_premiums: [
        { member_identifier: applicant_1.person_hbx_id, monthly_premium: 100.00 },
        { member_identifier: applicant_2.person_hbx_id, monthly_premium: 101.00 }
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
      aptc_csr_eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant, current_state: 'pending')
      old_state = FactoryBot.build(:v3_state_history, created_at: 2.days.ago)
      new_state = FactoryBot.build(:v3_state_history, created_at: 1.day.ago)
      aptc_csr_eligibility.state_histories << old_state
      aptc_csr_eligibility.state_histories << new_state
      aptc_csr_eligibility.save!
      FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::IncomeEvidence', key: :income_evidence, current_state: 'pending')
    end

    allow(subject).to receive(:build_event).and_return(event)
    allow(subject).to receive(:publish).and_return(Success("Event published successfully"))
    allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
    allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
    allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
    family.update_attributes(latest_application_gid: application.to_global_id.uri.to_s)
  end

  let(:payload_entity) { ::Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application).value! }

  context 'with valid application' do
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      @result = subject.call({application_hbx_id: application.hbx_id})
      application.reload
    end

    it 'should return success' do
      expect(@result).to be_success
      family.reload
      expect(family.eligibility_determination.application_gid).to eq application.to_global_id.uri.to_s
    end

    it 'should record failure for valid applicant1' do
      income_evidence = application.applicants[0].aptc_csr_eligibility.income_evidence
      expect(income_evidence.verification_histories.count).to eq 1
      expect(income_evidence.verification_histories.last.action).to eq 'rrv_submitted'
    end

    it 'income_evidence state for valid applicant1 is pending' do
      income_evidence = application.applicants[0].aptc_csr_eligibility.income_evidence
      expect(income_evidence.current_state).to eq :pending
    end

    it 'should record failure for invalid applicant' do
      income_evidence = application.applicants[1].aptc_csr_eligibility.income_evidence
      expect(income_evidence.verification_histories.count).to eq 1
      expect(income_evidence.verification_histories.last.action).to eq 'rrv_submitted'
    end

    it 'income_evidence for invalid applicant is pending' do
      income_evidence = application.applicants[1].aptc_csr_eligibility.income_evidence
      expect(income_evidence.current_state).to eq :pending
    end
  end

  context 'when invalid applicants' do
    context 'when applicant is invalid' do
      before do
        application.applicants.last.unset(:encrypted_ssn)
        application.save!
        @result = subject.call({ application_hbx_id: application.hbx_id })
        application.reload
      end

      it 'should return failure' do
        expect(@result).to be_failure
      end

      it 'should record failure for valid applicant1' do
        income_evidence = application.applicants[0].aptc_csr_eligibility.income_evidence
        expect(income_evidence.verification_histories.count).to eq 2
        expect(income_evidence.verification_histories.last.action).to eq 'rrv_submission_failed'
      end

      it 'income_evidence state for valid applicant1 is negative_response_received' do
        income_evidence = application.applicants[0].aptc_csr_eligibility.income_evidence
        expect(income_evidence.current_state).to eq :negative_response_received
      end

      it 'should record failure for invalid applicant' do
        income_evidence = application.applicants[1].aptc_csr_eligibility.income_evidence
        expect(income_evidence.verification_histories.count).to eq 2
        expect(income_evidence.verification_histories.last.action).to eq 'rrv_submission_failed'
      end

      it 'income_evidence for invalid applicant is negative_response_received' do
        income_evidence = application.applicants[1].aptc_csr_eligibility.income_evidence
        expect(income_evidence.current_state).to eq :negative_response_received
      end
    end

    context 'when all applicants are invalid' do
      before do
        application.applicants.each do |applicant|
          applicant.unset(:encrypted_ssn)
        end
        application.save!
        @result = subject.call({ application_hbx_id: application.hbx_id })
        application.reload
      end

      it 'should return failure' do
        expect(@result).to be_failure
      end

      it 'should record failure for invalid applicant1' do
        income_evidence = application.applicants[0].aptc_csr_eligibility.income_evidence
        expect(income_evidence.verification_histories.last.action).to eq 'rrv_submission_failed'
      end

      it 'income_evidence for invalid applicant1 is negative_response_received' do
        income_evidence = application.applicants[0].aptc_csr_eligibility.income_evidence
        expect(income_evidence.verification_histories.count).to eq 2
        expect(income_evidence.current_state).to eq :negative_response_received
      end

      it 'should record failure for invalid applicant1' do
        income_evidence = application.applicants[1].aptc_csr_eligibility.income_evidence
        expect(income_evidence.verification_histories.last.action).to eq 'rrv_submission_failed'
      end

      it 'income_evidence for invalid applicant1 is negative_response_received' do
        income_evidence = application.applicants[1].aptc_csr_eligibility.income_evidence
        expect(income_evidence.verification_histories.count).to eq 2
        expect(income_evidence.current_state).to eq :negative_response_received
      end
    end
  end
end