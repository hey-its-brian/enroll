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
    state_history.event == :move_to_verified &&
      state_history.from_state == :unverified &&
      state_history.to_state == :verified &&
      state_history.comment == 'Data Migration for post-V3 Evidence implementation Renewal Application' &&
      state_history.reason == 'Data Migration - V3 Evidence Records'
  end
end

RSpec.describe ::Operations::DataFixes::CreateV3AptcCsrEvidences, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442') }
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
                      renewal_base_year: TimeKeeper.date_of_record.year + 1)
  end

  let(:applicant) do
    FactoryBot.create(:applicant,
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
  end

  let(:dependent_person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true) }
  let(:dependent_family_member) { FactoryBot.create(:family_member, family: family, person: dependent_person) }
  let(:dependent_applicant) do
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
                                            is_primary_caregiver_for: [])
    dependent_applicant.build_aptc_eligibilities_evidences
    dependent_applicant.aptc_csr_eligibility.income_evidence.update(current_state: 'outstanding', is_satisfied: false, verification_outstanding: true)
    dependent_applicant
  end

  let(:dependent_person2) do
    dependent_person2 = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true)
    dependent_person2
  end

  let(:dependent_family_member2) { FactoryBot.create(:family_member, family: family, person: dependent_person2) }
  let(:dependent_applicant2) do
    FactoryBot.create(:applicant,
                      first_name: "dep_name2",
                      application: application,
                      dob: TimeKeeper.date_of_record - 30.years,
                      is_primary_applicant: false,
                      is_applying_coverage: false,
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
      applicant
      dependent_applicant
      dependent_applicant2
    end

    context 'before triggering the operation' do
      it 'checks initial evidence states' do
        primary_elig = applicant.aptc_csr_eligibility
        dependent_elig = dependent_applicant.aptc_csr_eligibility

        expect(application.applicants.count).to eq(3)

        expect(primary_elig&.income_evidence).to be_nil
        expect(primary_elig&.esi_mec_evidence).to be_nil
        expect(primary_elig&.non_esi_mec_evidence).to be_nil
        expect(primary_elig&.local_mec_evidence).to be_nil

        expect(dependent_elig.income_evidence).to be_present
        expect(dependent_elig.income_evidence.current_state).to eq(:outstanding)
        expect(dependent_elig.esi_mec_evidence).to be_present
        expect(dependent_elig.esi_mec_evidence.current_state).to eq(:pending)
        expect(dependent_elig.non_esi_mec_evidence).to be_present
        expect(dependent_elig.non_esi_mec_evidence.current_state).to eq(:pending)

        expect(dependent_applicant2.aptc_csr_eligibility).to be_nil
      end
    end

    context 'after triggering the operation' do
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
          primary_elig = applicant.aptc_csr_eligibility
          dependent_elig = dependent_applicant.aptc_csr_eligibility

          expect(primary_elig&.income_evidence).to be_nil
          expect(primary_elig&.esi_mec_evidence).to be_nil
          expect(primary_elig&.non_esi_mec_evidence).to be_nil
          expect(primary_elig&.local_mec_evidence).to be_nil

          expect(dependent_elig.income_evidence).to be_present
          expect(dependent_elig.income_evidence.current_state).to eq(:outstanding)
          expect(dependent_elig.esi_mec_evidence).to be_present
          expect(dependent_elig.esi_mec_evidence.current_state).to eq(:pending)
          expect(dependent_elig.non_esi_mec_evidence).to be_present
          expect(dependent_elig.non_esi_mec_evidence.current_state).to eq(:pending)

          expect(dependent_applicant2.aptc_csr_eligibility).to be_nil
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
          applicant1_eligibility = applicant1.aptc_csr_eligibility
          expect(applicant1_eligibility).to be_present
          expect(applicant1).to have_verified_evidence('income_evidence', :verified, true, false)
          expect(applicant1_eligibility.income_evidence).to have_state_histories
          expect(applicant1).to have_verified_evidence('esi_mec_evidence', :verified, true, false)
          expect(applicant1_eligibility.esi_mec_evidence).to have_state_histories
          expect(applicant1).to have_verified_evidence('non_esi_mec_evidence', :verified, true, false)
          expect(applicant1_eligibility.non_esi_mec_evidence).to have_state_histories
          expect(applicant1).to have_verified_evidence('local_mec_evidence', :verified, true, false)
          expect(applicant1_eligibility.local_mec_evidence).to have_state_histories
        end

        it 'creates verified evidences for applicant2' do
          applicant2 = application.applicants.where(id: dependent_applicant.id).first
          applicant2_eligibility = applicant2.aptc_csr_eligibility
          expect(applicant2_eligibility).to be_present
          expect(applicant2).to have_verified_evidence('income_evidence', :outstanding, false, true)
          expect(applicant2).to have_verified_evidence('esi_mec_evidence', :pending, true, false)
          expect(applicant2).to have_verified_evidence('non_esi_mec_evidence', :pending, true, false)
        end

        it 'creates verified evidences for applicant3' do
          applicant3 = application.applicants.where(id: dependent_applicant2.id).first
          applicant3_eligibility = applicant3.aptc_csr_eligibility
          expect(applicant3_eligibility).to be_present
          expect(applicant3).to have_verified_evidence('income_evidence', :verified, true, false)
          expect(applicant3_eligibility.income_evidence).to have_state_histories
          expect(applicant3_eligibility.esi_mec_evidence).to be_nil
          expect(applicant3_eligibility.non_esi_mec_evidence).to be_nil
          expect(applicant3_eligibility.local_mec_evidence).to be_nil
        end
      end
    end
  end
end
