# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Operations::Evidences::IncomeEvidences::AutoExtendDueDate, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }
  let(:ai_an_evidence) { FactoryBot.create(:american_indian_evidence, :verified, eligibility: ivl_eligibility) }
  let(:citizenship_evidence) { FactoryBot.create(:citizenship_evidence, :rejected, eligibility: ivl_eligibility) }
  let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :outstanding, eligibility: ivl_eligibility) }
  let(:fam_determination) { Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family) }
  let(:aptc_csr_eligibility)  { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:esi_evidence) { FactoryBot.create(:esi_mec_evidence, :pending, eligibility: aptc_csr_eligibility) }
  let(:local_evidence) { FactoryBot.create(:local_mec_evidence, :rejected, eligibility: aptc_csr_eligibility) }
  let(:non_esi_evidence) { FactoryBot.create(:non_esi_mec_evidence, :outstanding, eligibility: aptc_csr_eligibility) }
  let(:income_evidence) do
    FactoryBot.create(
      :income_evidence,
      current_state: income_state,
      due_on: income_due_on,
      due_date_extended_at: income_due_date_extended_at,
      eligibility: aptc_csr_eligibility
    )
  end

  let(:faa_application) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      aasm_state: 'determined',
      submitted_at: Time.now,
      assistance_year: TimeKeeper.date_of_record.year
    )
  end
  let(:applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      family_member_id: primary_applicant.id,
      person_hbx_id: person.hbx_id,
      application: faa_application
    )
  end
  let(:today) { TimeKeeper.date_of_record }

  let(:enrollment) do
    FactoryBot.create(
      :hbx_enrollment,
      :individual_unassisted,
      :health,
      :with_silver_health_product,
      household: family.active_household,
      coverage_kind: 'health',
      effective_on: TimeKeeper.date_of_record.beginning_of_month,
      family: family
    )
  end

  let(:enrollment_member) do
    FactoryBot.create(
      :hbx_enrollment_member,
      applicant_id: primary_applicant.id,
      hbx_enrollment: enrollment,
      coverage_start_on: enrollment.effective_on
    )
  end

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    esi_evidence
    income_evidence
    local_evidence
    non_esi_evidence
    alive_evidence
    ai_an_evidence
    citizenship_evidence
    ssn_evidence
    family.assign_latest_application_gid
    family.save!
    enrollment_member
    fam_determination
    @result = subject.call({ current_due_on: today })
  end

  context 'when:
    - income_evidence is outstanding
    - due_date is same as input_date
    - due_date is not extended previously
    ' do

    let(:income_state) { :outstanding }
    let(:income_due_on) { today }
    let(:income_due_date_extended_at) { nil }

    it 'extends the due date of income evidence' do
      expect(income_evidence.reload.due_on).not_to eq(today)
      expect(income_evidence.due_date_extended_at).not_to be_nil
      expect(income_evidence.verification_histories.count).to eq(1)
      expect(income_evidence.verification_histories.first).to have_attributes(
        action: 'auto_extend_due_date',
        updated_by: 'system'
      )
    end

    it "should build family determination and update due date of income evidence" do
      income_evidence.reload
      family.reload
      eligibility_state = family.eligibility_determination.subjects.first.eligibility_states.by_type("aptc_csr_credit").first
      evidence_state = eligibility_state.evidence_states.detect{|evi_state| evi_state.evidence_item_key == :income_evidence }
      expect(income_evidence.due_on).to eq(evidence_state.due_on)
    end
  end

  context 'when:
    - income_evidence is outstanding
    - due_date is in the future
    - due_date is extended previously
    ' do

    let(:income_state) { :outstanding }
    let(:income_due_on) { today + 5.days }
    let(:income_due_date_extended_at) { today - 1.day }

    it 'does not extend the due date of income evidence' do
      expect(income_evidence.reload.due_on).to eq(income_due_on)
      expect(income_evidence.due_date_extended_at).to eq(income_due_date_extended_at)
      expect(income_evidence.verification_histories.count).to eq(0)
    end
  end

  context 'when:
    - income_evidence is outstanding
    - due_date is in the future
    - due_date is not extended previously
    ' do

    let(:income_state) { :outstanding }
    let(:income_due_on) { today + 5.days }
    let(:income_due_date_extended_at) { nil }

    it 'does not extend the due date of income evidence' do
      expect(income_evidence.reload.due_on).to eq(income_due_on)
      expect(income_evidence.due_date_extended_at).to eq(income_due_date_extended_at)
      expect(income_evidence.verification_histories.count).to eq(0)
    end
  end

  context 'when:
    - income_evidence is rejected
    - due_date is same as input_date
    - due_date is not extended previously
    ' do

    let(:income_state) { :rejected }
    let(:income_due_on) { today }
    let(:income_due_date_extended_at) { nil }

    it 'extends the due date of income evidence' do
      expect(income_evidence.reload.due_on).not_to eq(income_due_on)
      expect(income_evidence.due_date_extended_at).not_to be_nil
      expect(income_evidence.verification_histories.count).to eq(1)
      expect(income_evidence.verification_histories.first).to have_attributes(
        action: 'auto_extend_due_date',
        updated_by: 'system'
      )
    end
  end

  context 'when:
    - income_evidence is rejected
    - due_date is in the future
    - due_date is extended previously
    ' do

    let(:income_state) { :rejected }
    let(:income_due_on) { today + 5.days }
    let(:income_due_date_extended_at) { today - 1.day }

    it 'does not extend the due date of income evidence' do
      expect(income_evidence.reload.due_on).to eq(income_due_on)
      expect(income_evidence.due_date_extended_at).to eq(income_due_date_extended_at)
      expect(income_evidence.verification_histories.count).to eq(0)
    end
  end

  context 'when:
    - income_evidence is rejected
    - due_date is in the future
    - due_date is not extended previously
    ' do

    let(:income_state) { :rejected }
    let(:income_due_on) { today + 5.days }
    let(:income_due_date_extended_at) { nil }

    it 'does not extend the due date of income evidence' do
      expect(income_evidence.reload.due_on).to eq(income_due_on)
      expect(income_evidence.due_date_extended_at).to eq(income_due_date_extended_at)
      expect(income_evidence.verification_histories.count).to eq(0)
    end
  end

  context 'when:
    - income_evidence is verified
    - due_date is nil
    - due_date is not extended previously
    ' do

    let(:income_state) { :verified }
    let(:income_due_on) { nil }
    let(:income_due_date_extended_at) { nil }

    it 'does not extend the due date of income evidence' do
      expect(income_evidence.reload.due_on).to eq(nil)
      expect(income_evidence.due_date_extended_at).to eq(nil)
      expect(income_evidence.verification_histories.count).to eq(0)
    end
  end
end
