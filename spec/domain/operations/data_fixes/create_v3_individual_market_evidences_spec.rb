# frozen_string_literal: true

require 'rails_helper'

RSpec::Matchers.define :have_verified_evidence do |evidence_type, current_state, is_satisfied, verification_outstanding|
  match do |applicant|
    evidence = applicant.fetch_v3_evidence(evidence_type)

    evidence.present? &&
      evidence.current_state == current_state &&
      evidence.is_satisfied == is_satisfied &&
      evidence.verification_outstanding == verification_outstanding
  end

  failure_message do |applicant|
    evidence = applicant.fetch_v3_evidence(evidence_type)
    "expected #{applicant} to have verified #{evidence_type}, but got #{evidence&.current_state}"
  end
end

RSpec::Matchers.define :have_state_histories do
  match do |evidence|
    return false unless evidence.state_histories.count == 1

    state_history = evidence.state_histories.first
    if evidence.key == 'alive_evidence'
      state_history.event == :move_to_unverified &&
        state_history.from_state == :initial &&
        state_history.to_state == :unverified &&
        state_history.comment == 'Data Migration for post-V3 Evidence implementation Renewal Application' &&
        state_history.reason == 'Data Migration - Alive evidence can only be moved to :outstanding or :attested by the DMF call'
    else
      state_history.event == :move_to_verified &&
        state_history.from_state == :unverified &&
        state_history.to_state == :verified &&
        state_history.comment == 'Data Migration for post-V3 Evidence implementation Renewal Application' &&
        state_history.reason == 'Data Migration - V3 Evidence Records'
    end
  end
end

RSpec.describe ::Operations::DataFixes::CreateV3IndividualMarketEvidences, dbclean: :after_each do
  let(:person) do
    person = FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442', encrypted_ssn: SymmetricEncryption.encrypt('472743442'))
    person.consumer_role.update(citizen_status: ConsumerRole::US_CITIZEN_STATUS)
    person
  end
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}

  let(:application) do
    FactoryBot.create(:application,
                      family_id: family.id,
                      aasm_state: 'determined',
                      effective_date: (TimeKeeper.date_of_record - 12.days),
                      origin: :user,
                      assistance_year: TimeKeeper.date_of_record.year,
                      generation_reason: :manual,
                      has_eligibility_response: true,
                      transfer_requested: true,
                      account_transferred: true,
                      has_mec_check_response: true,
                      applicant_kind: "user and/or family",
                      request_kind: "placeholder",
                      motivation_kind: "insurance_affordability",
                      us_state: "ME",
                      is_ridp_verified: true,
                      submitted_at: TimeKeeper.date_of_record - 30.days,
                      renewal_base_year: TimeKeeper.date_of_record.year + 1)
  end

  let(:applicant) do
    applicant = FactoryBot.create(:applicant,
                                  first_name: "app_name",
                                  application: application,
                                  dob: TimeKeeper.date_of_record - 40.years,
                                  is_primary_applicant: true,
                                  is_applying_coverage: true,
                                  family_member_id: family.family_members[0].id,
                                  person_hbx_id: person.hbx_id,
                                  addresses: [FactoryBot.build(:financial_assistance_address)],
                                  is_eligible_for_non_magi_reasons: true,
                                  magi_medicaid_category: "medicaid",
                                  medicaid_household_size: 3,
                                  magi_medicaid_monthly_household_income: 1000,
                                  magi_medicaid_monthly_income_limit: 2000,
                                  magi_as_percentage_of_fpl: 150,
                                  csr_percent_as_integer: 87,
                                  csr_eligibility_kind: "csr_87",
                                  benchmark_premiums: {"health_only_slcsp_premiums" => [{"member_identifier" => "1281306", "monthly_premium" => 1060.57}],
                                                       "health_only_lcsp_premiums" => [{"member_identifier" => "1281306", "monthly_premium" => 1058.99}]},
                                  contact_method: "Paper and Electronic communications",
                                  language_preference: "test",
                                  is_ia_eligible: true,
                                  is_csr_eligible: true,
                                  is_medicaid_chip_eligible: true,
                                  is_non_magi_medicaid_eligible: true,
                                  is_totally_ineligible: true,
                                  is_without_assistance: true,
                                  is_magi_medicaid: true,
                                  is_gap_filling: true,
                                  is_primary_caregiver_for: [])

    applicant.build_individual_market_eligibility
    applicant.save!
    applicant
  end

  let(:dependent_person) do
    person2 = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true, encrypted_ssn: nil, no_ssn: '1')
    person2.consumer_role.update(citizen_status: ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS)
    person2
  end

  let(:dependent_family_member) { FactoryBot.create(:family_member, family: family, person: dependent_person) }
  let!(:dependent_applicant) do
    dependent_applicant = FactoryBot.create(:applicant,
                                            first_name: "dep_name",
                                            application: application,
                                            dob: TimeKeeper.date_of_record - 40.years,
                                            is_primary_applicant: false,
                                            is_applying_coverage: true,
                                            family_member_id: dependent_family_member.id,
                                            person_hbx_id: dependent_person.hbx_id,
                                            addresses: [FactoryBot.build(:financial_assistance_address)],
                                            is_eligible_for_non_magi_reasons: true,
                                            magi_medicaid_category: "medicaid",
                                            medicaid_household_size: 3,
                                            magi_medicaid_monthly_household_income: 1000,
                                            magi_medicaid_monthly_income_limit: 2000,
                                            magi_as_percentage_of_fpl: 150,
                                            csr_percent_as_integer: 87,
                                            csr_eligibility_kind: "csr_87",
                                            benchmark_premiums: {"health_only_slcsp_premiums" => [{"member_identifier" => dependent_person.hbx_id, "monthly_premium" => 1060.57}],
                                                                 "health_only_lcsp_premiums" => [{"member_identifier" => dependent_person.hbx_id, "monthly_premium" => 1058.99}]},
                                            contact_method: "Paper and Electronic communications",
                                            language_preference: "test",
                                            is_ia_eligible: true,
                                            is_csr_eligible: true,
                                            is_medicaid_chip_eligible: true,
                                            is_non_magi_medicaid_eligible: true,
                                            is_totally_ineligible: true,
                                            is_without_assistance: true,
                                            is_magi_medicaid: true,
                                            is_gap_filling: true,
                                            is_primary_caregiver_for: [],
                                            citizen_status: ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS)
    dependent_applicant.build_ivl_eligibility_with_evidences
    dependent_applicant.save!
    dependent_applicant
  end

  let(:dependent_person2) do
    person3 = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true, ssn: '573849302', encrypted_ssn: SymmetricEncryption.encrypt('573849302'))
    person3.indian_tribe_member = true
    person3.consumer_role.update!(citizen_status: ConsumerRole::US_CITIZEN_STATUS, american_indian_status: true, is_applying_coverage: true, tribal_id: "4848477", tribal_name: 'Micmac', tribal_state: 'ME', tribe_codes: ['123456'])
    person3.save!
    person3
  end

  let(:dependent_family_member2) { FactoryBot.create(:family_member, family: family, person: dependent_person2) }
  let(:dependent_applicant2) do
    FactoryBot.create(:applicant,
                      first_name: "dep_name2",
                      application: application,
                      dob: TimeKeeper.date_of_record - 30.years,
                      is_primary_applicant: false,
                      is_applying_coverage: true,
                      family_member_id: dependent_family_member2.id,
                      person_hbx_id: dependent_person2.hbx_id,
                      addresses: [FactoryBot.build(:financial_assistance_address)],
                      is_eligible_for_non_magi_reasons: true,
                      magi_medicaid_category: "medicaid",
                      medicaid_household_size: 3,
                      magi_medicaid_monthly_household_income: 1000,
                      magi_medicaid_monthly_income_limit: 2000,
                      magi_as_percentage_of_fpl: 150,
                      csr_percent_as_integer: 87,
                      csr_eligibility_kind: "csr_87",
                      benchmark_premiums: {"health_only_slcsp_premiums" => [{"member_identifier" => dependent_person2.hbx_id, "monthly_premium" => 1060.57}],
                                           "health_only_lcsp_premiums" => [{"member_identifier" => dependent_person2.hbx_id, "monthly_premium" => 1058.99}]},
                      contact_method: "Paper and Electronic communications",
                      language_preference: "test",
                      is_ia_eligible: true,
                      is_csr_eligible: true,
                      is_medicaid_chip_eligible: true,
                      is_non_magi_medicaid_eligible: true,
                      is_totally_ineligible: true,
                      is_without_assistance: true,
                      is_magi_medicaid: true,
                      is_gap_filling: true,
                      is_primary_caregiver_for: [])
  end

  let(:params) { {application_hbx_id: application.hbx_id} }

  describe "invalid params" do
    it "should fail" do
      result = described_class.new.call({application_hbx_id: nil})
      expect(result).to be_failure
      expect(result.failure).to eq("application_hbx_id is missing")
    end
  end

  describe "evidence creation" do
    before do
      allow(EnrollRegistry[:ai_an_self_attestation].feature).to receive(:is_enabled).and_return(true)
      applicant
      dependent_applicant
      dependent_applicant2
    end

    context 'before triggering the operation' do
      it 'checks initial evidence states' do
        primary_elig = applicant.individual_market_eligibility
        dependent_elig = dependent_applicant.individual_market_eligibility

        expect(application.applicants.count).to eq(3)

        expect(primary_elig&.social_security_number_evidence).to be_nil
        expect(primary_elig&.citizenship_evidence).to be_nil
        expect(primary_elig&.alive_evidence).to be_nil

        expect(dependent_elig.social_security_number_evidence).to_not be_present
        expect(dependent_elig.citizenship_evidence).to_not be_present
        expect(dependent_elig.alive_evidence).to_not be_present
        expect(dependent_elig.immigration_evidence).to be_present
        expect(dependent_elig.immigration_evidence.current_state).to eq(:pending)

        expect(dependent_applicant2.individual_market_eligibility).to be_nil
      end
    end

    context 'when the family has a more recent determined application' do
      before do
        submission_time = TimeKeeper.date_of_record - 10.days
        effective_date = (TimeKeeper.date_of_record - 5.days)
        FactoryBot.create(:application, family_id: family.id, aasm_state: 'determined', effective_date: effective_date, assistance_year: effective_date.year, submitted_at: submission_time)
        family.assign_latest_application_gid
      end

      it 'should fail if there is a more recent determined application' do
        params[:action] = 'data_fix'
        result = described_class.new.call(params)
        expect(result).to be_failure
        expect(result.failure).to eq('Application is not latest determined application for family')
      end
    end

    context 'after triggering the operation' do
      before do
        allow(dependent_person2.consumer_role).to receive(:ai_or_an_tribe_member?).and_return(true)
      end

      context 'with report mode enabled' do
        before do
          params[:action] = 'report'
          @result = described_class.new.call(params)
          application.reload
        end

        it 'should be successful' do
          expect(@result).to be_success
        end

        it 'does not create any evidences for any applicants' do
          primary_elig = applicant.individual_market_eligibility
          dependent_elig = dependent_applicant.individual_market_eligibility

          expect(application.applicants.count).to eq(3)

          expect(primary_elig&.social_security_number_evidence).to be_nil
          expect(primary_elig&.citizenship_evidence).to be_nil
          expect(primary_elig&.alive_evidence).to be_nil

          expect(dependent_elig.social_security_number_evidence).to_not be_present
          expect(dependent_elig.citizenship_evidence).to_not be_present
          expect(dependent_elig.alive_evidence).to_not be_present
          expect(dependent_elig.immigration_evidence).to be_present
          expect(dependent_elig.immigration_evidence.current_state).to eq(:pending)

          expect(dependent_applicant2.individual_market_eligibility).to be_nil
        end
      end

      context 'with report mode disabled' do
        before do
          params[:action] = 'data_fix'
          @result = described_class.new.call(params)
          application.reload
        end

        it 'should be successful' do
          expect(@result).to be_success
        end

        it 'creates verified evidences for applicant1' do
          applicant1 = application.primary_applicant
          applicant1_eligibility = applicant1.individual_market_eligibility
          expect(applicant1_eligibility).to be_present
          expect(applicant1).to have_verified_evidence('social_security_number_evidence', :verified, true, false)
          expect(applicant1_eligibility.social_security_number_evidence).to have_state_histories
          expect(applicant1).to have_verified_evidence('citizenship_evidence', :verified, true, false)
          expect(applicant1_eligibility.citizenship_evidence).to have_state_histories
          expect(applicant1).to have_verified_evidence('alive_evidence', :unverified, true, false)
          expect(applicant1_eligibility.alive_evidence).to have_state_histories
          expect(applicant1_eligibility.immigration_evidence).to_not be_present
          expect(applicant1_eligibility.american_indian_evidence).to_not be_present
        end

        it 'creates verified evidences for applicant2' do
          applicant2 = application.applicants.where(id: dependent_applicant.id).first
          applicant2_eligibility = applicant2.individual_market_eligibility
          expect(applicant2_eligibility).to be_present
          expect(applicant2_eligibility.citizenship_evidence).to_not be_present
          expect(applicant2_eligibility.social_security_number_evidence).to_not be_present
          expect(applicant2_eligibility.alive_evidence).to_not be_present
          expect(applicant2).to have_verified_evidence('immigration_evidence', :pending, true, false)
        end

        it 'creates verified evidences for applicant3' do
          applicant3 = application.applicants.where(id: dependent_applicant2.id).first
          applicant3_eligibility = applicant3.individual_market_eligibility
          expect(applicant3_eligibility).to be_present
          expect(applicant3).to have_verified_evidence('social_security_number_evidence', :verified, true, false)
          expect(applicant3_eligibility.social_security_number_evidence).to have_state_histories
          expect(applicant3).to have_verified_evidence('citizenship_evidence', :verified, true, false)
          expect(applicant3_eligibility.citizenship_evidence).to have_state_histories
          expect(applicant3).to have_verified_evidence('alive_evidence', :unverified, true, false)
          expect(applicant3_eligibility.alive_evidence).to have_state_histories
          expect(applicant3).to have_verified_evidence('american_indian_evidence', :verified, true, false)
          expect(applicant3_eligibility.american_indian_evidence).to have_state_histories
        end
      end
    end
  end
end
