# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Families::Verifications::Summary::IndividualQuery, dbclean: :after_each do
  subject { described_class.new }

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  before :all do
    # Set up the environment variables to enable the features
    ENV['ENABLE_ALIVE_STATUS'] = 'true'
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = 'true'
    ENV['QHP_APPLICATION_IS_ENABLED'] = 'true'
    ENV['SHOW_PREVIOUS_YEAR_FAA_VERIFICATIONS_IS_ENABLED'] = 'true'
    ENV['SHOW_INACTIVE_VERIFICATIONS_IS_ENABLED'] = 'true'

    # Now load the registry initializer after ENV variables are set
    load Rails.root.join('config', 'initializers', 'enroll_registry.rb')
  end

  after :all do
    # Clean up the environment variables after the tests
    ENV['ENABLE_ALIVE_STATUS'] = nil
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = nil
    ENV['QHP_APPLICATION_IS_ENABLED'] = nil
    ENV['SHOW_PREVIOUS_YEAR_FAA_VERIFICATIONS_IS_ENABLED'] = nil
    ENV['SHOW_INACTIVE_VERIFICATIONS_IS_ENABLED'] = nil

    # Now load the registry initializer after ENV variables are reset
    load Rails.root.join('config', 'initializers', 'enroll_registry.rb')
  end

  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }
  let(:ai_an_evidence) { FactoryBot.create(:american_indian_evidence, :with_verification_histories, :verified, eligibility: ivl_eligibility) }
  let(:citizenship_evidence) { FactoryBot.create(:citizenship_evidence, :with_verification_histories, :rejected, eligibility: ivl_eligibility) }
  let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }
  let(:esi_evidence) { FactoryBot.create(:esi_mec_evidence, :with_verification_histories, :pending, eligibility: aptc_csr_eligibility) }
  let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories,  :verified, eligibility: aptc_csr_eligibility) }
  let(:local_evidence) { FactoryBot.create(:local_mec_evidence, :with_verification_histories, :rejected, eligibility: aptc_csr_eligibility) }
  let(:non_esi_evidence) { FactoryBot.create(:non_esi_mec_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }

  let(:determination) { ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family) }
  let(:primary_subject) { result.success.subjects.first }
  let(:aca_ivl_credit) { primary_subject.eligibility_states.where(eligibility_item_key: :aca_individual_market_eligibility).first }
  let(:aptc_csr_eligibility)  { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:aptc_csr_credit) { primary_subject.eligibility_states.where(eligibility_item_key: :aptc_csr_credit).first }

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

  before :each do
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

  context 'invalid params' do
    it 'returns an error when family is not provided' do
      determination
      result = subject.call({})
      expect(result.failure?).to be true
      expect(result.failure).to eq('Family is missing')
    end

    it 'returns an error when person_id is not provided' do
      determination
      result = subject.call({ family: family })
      expect(result.failure?).to be true
      expect(result.failure).to eq('Person ID is missing')
    end
  end

  context 'valid params' do
    it 'returns member and evidences for a valid family and person_id' do
      determination
      params = { family: family, person_id: person.id }
      result = subject.call(params)

      expect(result.success?).to be true
      expect(result.success[:member]).to eq(family.primary_applicant)
      expect(result.success[:evidences].size).to eq(10)
      expect(result.success[:evidences].all? { |e| e.is_a?(Adapters::EvidenceAdapter) }).to be true
    end
  end

  context 'when inactive verifications are present' do
    let(:qhp_application) { FactoryBot.create(:individual_market_application, :determined, family_id: family.id) }
    let(:qhp_applicant) { FactoryBot.create(:individual_market_applicant, :with_person_name, :with_demographics, :with_eligibilities, application: qhp_application, family_member_id: primary_applicant.id) }

    before do
      qhp_application
      qhp_applicant.build_individual_market_evidences
      qhp_application.save!
      family.update_attributes!(latest_application_gid: qhp_application.to_global_id.to_s)
    end

    it 'returns member, evidences and inactive verifications for a valid family and person_id' do
      determination
      params = { family: family, person_id: person.id }
      result = subject.call(params)
      expect(result.success?).to be true
      success = result.success
      evidences = success[:evidences]
      inactive_evidences = evidences.select(&:inactive)
      expect(success[:member]).to eq(family.primary_applicant)
      expect(evidences.size).to eq(8)
      expect(evidences.all? { |e| e.is_a?(Adapters::EvidenceAdapter) }).to be true
      expect(inactive_evidences.size).to eq(7)
      expect(inactive_evidences.map(&:evidence_item_key)).to include(:income_evidence)
    end
  end
end
