=begin
The tests run by this spec are obsolete, as V3 evidences types have already supplanted
the original evidences

# frozen_string_literal: true

require 'rails_helper'

RSpec::Matchers.define :have_verified_evidence do |evidence_type, aasm_state, is_satisfied, verification_outstanding|
  match do |applicant|
    evidence = applicant.send(evidence_type)

    evidence.present? &&
      evidence.aasm_state == aasm_state &&
      evidence.is_satisfied == is_satisfied &&
      evidence.verification_outstanding == verification_outstanding
  end

  failure_message do |applicant|
    evidence = applicant.send(evidence_type)
    "expected #{applicant} to have verified #{evidence_type}, but got #{evidence&.aasm_state}"
  end
end

RSpec::Matchers.define :have_verification_history do
  match do |evidence|
    return false unless evidence.verification_histories.count == 1

    history = evidence.verification_histories.first
    history.action == 'Data Migration' &&
      history.update_reason == 'Data Migration - Evidence Records' &&
      history.updated_by == 'Admin'
  end
end

RSpec::Matchers.define :have_workflow_state_transition do
  match do |evidence|
    return false unless evidence.workflow_state_transitions.count == 1

    workflow_state_transition = evidence.workflow_state_transitions.first
    workflow_state_transition.event == 'move_to_verified' &&
      workflow_state_transition.from_state == 'unverified' &&
      workflow_state_transition.to_state == 'verified'
  end
end

RSpec.describe ::Operations::DataFixes::CreateAptcCsrEvidences, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442') }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}

  let(:application) do
    FactoryBot.create(:application,
                      family_id: family.id,
                      aasm_state: "determined",
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
                      first_name: "app_nmae",
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
    FactoryBot.create(:applicant,
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
  end

  let!(:income_evidence) do
    dependent_applicant.create_income_evidence(key: :income,
                                               title: 'Income',
                                               aasm_state: 'outstanding',
                                               due_on: TimeKeeper.date_of_record + 30.days,
                                               verification_outstanding: true,
                                               is_satisfied: false,
                                               external_service: 'FDSH IFSV',
                                               updated_by: "admin",
                                               description: 'Income')
  end

  let!(:esi_evidence) do
    dependent_applicant.create_esi_evidence(key: :esi_mec,
                                            title: 'ESI MEC',
                                            aasm_state: 'verified',
                                            due_on: TimeKeeper.date_of_record + 30.days,
                                            verification_outstanding: false,
                                            is_satisfied: true,
                                            external_service: 'FDSH IFSV',
                                            updated_by: "admin",
                                            description: 'ESI MEC')
  end

  let(:dependent_person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, age_off_excluded: true) }
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
        expect(application.applicants.count).to eq(3)
        expect(applicant.income_evidence).to be_nil
        expect(applicant.esi_evidence).to be_nil
        expect(applicant.non_esi_evidence).to be_nil
        expect(applicant.local_mec_evidence).to be_nil
        expect(dependent_applicant.income_evidence).to be_present
        expect(dependent_applicant.income_evidence.aasm_state).to eq("outstanding")
        expect(dependent_applicant.esi_evidence).to be_present
        expect(dependent_applicant.esi_evidence.aasm_state).to eq("verified")
        expect(dependent_applicant.non_esi_evidence).to be_nil
        expect(dependent_applicant.local_mec_evidence).to be_nil
        expect(dependent_applicant2.income_evidence).to be_nil
        expect(dependent_applicant2.esi_evidence).to be_nil
        expect(dependent_applicant2.non_esi_evidence).to be_nil
        expect(dependent_applicant2.local_mec_evidence).to be_nil
      end
    end

    context 'applicant callbacks when evidence is saved' do
      it 'triggers applicant callbacks when creating evidences' do
        applicant_ids = []
        allow_any_instance_of(FinancialAssistance::Applicant).to receive(:propagate_applicant) do |applicant|
          applicant_ids << applicant.id
        end

        result = described_class.new.call(params)
        expect(result).to be_success
        expect(applicant_ids).to be_empty
      end
    end

    context 'after triggering the operation' do
      before do
        @result = described_class.new.call(params)
        application.reload
      end

      it 'creates verified evidences for applicant1' do
        expect(@result).to be_success
        applicant1 = application.primary_applicant
        expect(applicant1).to have_verified_evidence(:income_evidence, 'verified', true, false)
        expect(applicant1.income_evidence).to have_verification_history
        expect(applicant1.income_evidence).to have_workflow_state_transition
        expect(applicant1).to have_verified_evidence(:esi_evidence, 'verified', true, false)
        expect(applicant1.esi_evidence).to have_verification_history
        expect(applicant1.esi_evidence).to have_workflow_state_transition
        expect(applicant1).to have_verified_evidence(:non_esi_evidence, 'verified', true, false)
        expect(applicant1.non_esi_evidence).to have_verification_history
        expect(applicant1.non_esi_evidence).to have_workflow_state_transition
        expect(applicant1).to have_verified_evidence(:local_mec_evidence, 'verified', true, false)
        expect(applicant1.local_mec_evidence).to have_verification_history
        expect(applicant1.local_mec_evidence).to have_workflow_state_transition
      end

      it 'creates verified evidences for applicant2' do
        applicant2 = application.applicants.where(id: dependent_applicant.id).first
        expect(applicant2).to have_verified_evidence(:income_evidence, 'outstanding', false, true)
        expect(applicant2).to have_verified_evidence(:esi_evidence, 'verified', true, false)
        expect(applicant2).to have_verified_evidence(:non_esi_evidence, 'verified', true, false)
        expect(applicant2.non_esi_evidence).to have_verification_history
        expect(applicant2.non_esi_evidence).to have_workflow_state_transition
        expect(applicant2).to have_verified_evidence(:local_mec_evidence, 'verified', true, false)
        expect(applicant2.local_mec_evidence).to have_verification_history
        expect(applicant2.local_mec_evidence).to have_workflow_state_transition
      end

      it 'creates verified evidences for applicant3' do
        applicant3 = application.applicants.where(id: dependent_applicant2.id).first
        expect(applicant3).to have_verified_evidence(:income_evidence, 'verified', true, false)
        expect(applicant3.income_evidence).to have_verification_history
        expect(applicant3.income_evidence).to have_workflow_state_transition
        expect(applicant3.esi_evidence).to be_nil
        expect(applicant3.non_esi_evidence).to be_nil
        expect(applicant3.local_mec_evidence).to be_nil
      end
    end
  end
end

=end