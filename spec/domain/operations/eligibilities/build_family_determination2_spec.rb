# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Eligibilities::BuildFamilyDetermination, type: :model, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  before :all do
    # Set up the environment variables to enable the features
    ENV['ENABLE_ALIVE_STATUS'] = 'true'
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = 'true'
    ENV['QHP_APPLICATION_IS_ENABLED'] = 'true'

    # Now load the registry initializer after ENV variables are set
    load Rails.root.join('config', 'initializers', 'enroll_registry.rb')
  end

  describe '#call' do
    let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
    let(:alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }
    let(:ai_an_evidence) { FactoryBot.create(:american_indian_evidence, :verified, eligibility: ivl_eligibility) }
    let(:citizenship_evidence) { FactoryBot.create(:citizenship_evidence, :rejected, eligibility: ivl_eligibility) }
    let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :outstanding, eligibility: ivl_eligibility) }

    let(:result) { subject.call(family: family) }
    let(:primary_subject) { result.success.subjects.first }
    let(:aca_ivl_credit) { primary_subject.eligibility_states.where(eligibility_item_key: :aca_individual_market_eligibility).first }
    let(:aptc_csr_eligibility)  { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }

    context 'when family has no applications' do
      it 'returns a failure' do
        expect(result.success?).to be_falsey
        expect(result.failure).to eq('Family does not have any applications.')
      end
    end

    context 'when family has financial assistance application' do
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

      let(:esi_evidence) { FactoryBot.create(:esi_mec_evidence, :pending, eligibility: aptc_csr_eligibility) }
      let(:income_evidence) { FactoryBot.create(:income_evidence, :verified, eligibility: aptc_csr_eligibility) }
      let(:local_evidence) { FactoryBot.create(:local_mec_evidence, :rejected, eligibility: aptc_csr_eligibility) }
      let(:non_esi_evidence) { FactoryBot.create(:non_esi_mec_evidence, :outstanding, eligibility: aptc_csr_eligibility) }

      let(:thhg) do
        FactoryBot.create(
          :tax_household_group,
          :active_current_year,
          application_id: faa_application.id,
          application_hbx_id: faa_application.hbx_id,
          family: family
        )
      end

      let(:thh) do
        thhg.tax_households.build(
          effective_starting_on: TimeKeeper.date_of_record.beginning_of_year,
          effective_ending_on: nil,
          submitted_at: TimeKeeper.date_of_record,
          is_eligibility_determined: true,
          yearly_expected_contribution: 1000.00,
          max_aptc: 200.00
        )
      end

      let(:thhm) { FactoryBot.create(:tax_household_member, tax_household: thh, applicant_id: primary_applicant.id) }

      before :each do
        thhm
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
      end

      let(:aptc_csr_credit) { primary_subject.eligibility_states.where(eligibility_item_key: :aptc_csr_credit).first }

      let(:aptc_grant) { result.success.grants.first }

      it 'returns success' do
        expect(result.success?).to be_truthy
      end

      it 'returns family eligibility determination' do
        expect(result.success).to be_a_kind_of(::Eligibilities::Determination)
      end

      it 'returns family eligibility determination with all the subjects' do
        expect(primary_subject.person_id).to eq(person.id.to_s)
      end

      it 'returns the subject with all the expected eligibility states' do
        expect(
          primary_subject.eligibility_states.map(&:eligibility_item_key).sort
        ).to eq(
          %w[aca_individual_market_eligibility aptc_csr_credit dental_product_enrollment_status health_product_enrollment_status]
        )
      end

      it 'returns the aptc_csr_credit eligibility state with all the expected evidence states' do
        expect(
          aptc_csr_credit.evidence_states.map(&:evidence_item_key).sort
        ).to eq(
          %i[esi_evidence income_evidence local_mec_evidence non_esi_evidence]
        )
      end

      it 'returns the aca_individual_market_eligibility eligibility state with all the expected evidence states' do
        expect(
          aca_ivl_credit.evidence_states.map(&:evidence_item_key).sort
        ).to eq(
          %i[alive_status american_indian_status citizenship social_security_number]
        )
      end

      it 'creates aptc_grant' do
        expect(aptc_grant).to be_a(::Eligibilities::Grant)
        expect(aptc_grant.title).to eq('aptc_grant')
        expect(aptc_grant.member_ids).to eq([primary_applicant.id.to_s])
        expect(aptc_grant.assistance_year).to eq(TimeKeeper.date_of_record.year)
        expect(aptc_grant.tax_household_group_id).to eq(thhg.id.to_s)
        expect(aptc_grant.tax_household_id).to eq(thh.id.to_s)
        expect(aptc_grant.value).to eq(thh.yearly_expected_contribution.to_s)
      end
    end

    context 'when family has qhp application' do
      let(:qhp_application) { FactoryBot.create(:individual_market_application, family_id: family.id, current_state: 'determined') }

      let(:applicant) do
        FactoryBot.create(
          :individual_market_applicant,
          :with_person_name,
          :with_demographics,
          family_member_id: primary_applicant.id,
          application: qhp_application
        )
      end

      let(:thhg) do
        FactoryBot.create(
          :tax_household_group,
          :active_current_year,
          source: 'qhp',
          application_id: qhp_application.id,
          application_hbx_id: qhp_application.hbx_id,
          family: family
        )
      end

      let(:thh) do
        thhg.tax_households.build(
          effective_starting_on: TimeKeeper.date_of_record.beginning_of_year,
          effective_ending_on: nil,
          submitted_at: TimeKeeper.date_of_record,
          is_eligibility_determined: true
        )
      end

      let(:thhm) do
        FactoryBot.create(
          :tax_household_member,
          is_uqhp_eligible: true,
          is_csr_eligible: true,
          is_ia_eligible: false,
          csr_eligibility_kind: 'csr_limited',
          csr_percent_as_integer: -1,
          tax_household: thh,
          applicant_id: primary_applicant.id
        )
      end

      let(:aptc_csr_eligibility_state) { primary_subject.eligibility_states.where(eligibility_item_key: :aptc_csr_credit).first }
      let(:csr_grant) { aptc_csr_eligibility_state.grants.where(key: 'CsrAdjustmentGrant').first }

      before :each do
        thhm
        aptc_csr_eligibility
        alive_evidence
        ai_an_evidence
        citizenship_evidence
        ssn_evidence
        family.assign_latest_application_gid
        family.save!
      end

      it 'returns success' do
        expect(result.success?).to be_truthy
      end

      it 'returns family eligibility determination' do
        expect(result.success).to be_a_kind_of(::Eligibilities::Determination)
      end

      it 'returns family eligibility determination with all the subjects' do
        expect(primary_subject.person_id).to eq(person.id.to_s)
      end

      it 'returns the subject with all the expected eligibility states' do
        expect(
          primary_subject.eligibility_states.map(&:eligibility_item_key).sort
        ).to eq(
          %w[aca_individual_market_eligibility aptc_csr_credit dental_product_enrollment_status health_product_enrollment_status]
        )
      end

      it 'returns the aca_ivl_credit eligibility state with all the expected evidence states' do
        expect(
          aca_ivl_credit.evidence_states.map(&:evidence_item_key).sort
        ).to eq(
          %i[alive_status american_indian_status citizenship social_security_number]
        )
      end

      it 'creates csr_grant' do
        expect(csr_grant).to be_a(::Eligibilities::Grant)
        expect(csr_grant.title).to eq('csr_grant')
        expect(csr_grant.key).to eq('CsrAdjustmentGrant')
        expect(csr_grant.assistance_year).to eq(TimeKeeper.date_of_record.year)
        expect(csr_grant.member_ids).to eq([primary_applicant.id.to_s])
      end

      it 'does not create aptc evidence_states' do
        expect(aptc_csr_eligibility_state.evidence_states).to be_empty
      end
    end
  end
end
