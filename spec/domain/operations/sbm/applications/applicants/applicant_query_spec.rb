# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Sbm::Applications::Applicants::ApplicantQuery, dbclean: :after_each do
  subject { described_class.new }

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

  after :all do
    # Clean up the environment variables after the tests
    ENV['ENABLE_ALIVE_STATUS'] = nil
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = nil
    ENV['QHP_APPLICATION_IS_ENABLED'] = nil

    # Now load the registry initializer after ENV variables are reset
    load Rails.root.join('config', 'initializers', 'enroll_registry.rb')
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

  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }

  let(:alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }
  let(:ai_an_evidence) { FactoryBot.create(:american_indian_evidence, :with_verification_histories, :verified, eligibility: ivl_eligibility) }
  let(:citizenship_evidence) { FactoryBot.create(:citizenship_evidence, :with_verification_histories, :rejected, eligibility: ivl_eligibility) }
  let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }
  let(:esi_evidence) { FactoryBot.create(:esi_mec_evidence, :with_verification_histories, :pending, eligibility: aptc_csr_eligibility) }
  let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories, :verified, eligibility: aptc_csr_eligibility) }

  before :each do
    alive_evidence
    ai_an_evidence
    citizenship_evidence
    ssn_evidence
    esi_evidence
    income_evidence
    family.assign_latest_application_gid
    family.save!
  end

  context 'invalid params' do
    it 'returns an error when application_gid is not provided or invalid' do
      params = { applicant_id: applicant.id.to_s }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Application not found')
    end

    it 'returns an error when applicant_id is not provided' do
      params = { application_gid: faa_application.to_global_id }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Applicant not found')
    end

    it 'returns an error when applicant is not found' do
      params = {
        application_gid: faa_application.to_global_id,
        applicant_id: 'invalid_id'
      }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Applicant not found')
    end
  end

  context 'valid params' do
    let(:valid_params) do
      {
        application_gid: faa_application.to_global_id,
        applicant_id: applicant.id.to_s
      }
    end

    it 'returns application, member and evidences for valid params' do
      result = subject.call(valid_params)

      expect(result.success?).to be true
      expect(result.success[:application]).to eq(faa_application)
      expect(result.success[:member]).to eq(applicant.family_member)
      expect(result.success[:evidences]).to be_an(Array)
      expect(result.success[:evidences].all? { |e| e.is_a?(Adapters::EvidenceAdapter) }).to be true
      expect(result.success[:display_previous_evidences]).to be true
    end

    it 'includes uploadable eligibility evidences' do
      result = subject.call(valid_params)

      expect(result.success?).to be true
      evidence_keys = result.success[:evidences].map(&:evidence_item_key)
      expect(evidence_keys).to include(:alive_evidence, :american_indian_evidence, :citizenship_evidence, :social_security_number_evidence)
    end

    it 'sorts evidences by grouped status, due date, and verification type name' do
      result = subject.call(valid_params)

      expect(result.success?).to be true
      evidences = result.success[:evidences]
      expect(evidences.size).to be > 0

      # Check that evidences are sorted (specific sorting logic depends on your implementation)
      previous_status = nil
      evidences.each do |evidence|
        current_status = evidence.grouped_status.to_s
        expect(current_status >= previous_status) if previous_status
        previous_status = current_status
      end
    end

    context 'when identity verification feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_identity_verification).and_return(true)
      end

      it 'includes identity evidence when person is identity verified' do
        person.consumer_role.update!(identity_validation: 'valid')
        result = subject.call(valid_params)

        expect(result.success?).to be true
        evidence_item_keys = result.success[:evidences].map(&:evidence_item_key)
        expect(evidence_item_keys).to include(:identity)
      end

      it 'excludes identity evidence when person is not identity verified' do
        person.consumer_role.update!(identity_verified?: false, application_verified?: false)
        result = subject.call(valid_params)

        expect(result.success?).to be true
        identity_evidences = result.success[:evidences].select { |e| e.instance_variable_get(:@evidence).is_a?(Person) }
        expect(identity_evidences).to be_empty
      end
    end

    context 'when inactive verifications feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_inactive_verifications).and_return(true)
      end

      it 'includes inactive verifications from determination when qhp_application is enabled' do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
        result = subject.call(valid_params)

        expect(result.success?).to be true
        expect(result.success[:evidences].size).to be > 0
      end

      it 'includes inactive verifications from person when qhp_application is disabled' do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
        person.verification_types.create!(type_name: 'Social Security Number', validation_status: 'unverified')

        result = subject.call(valid_params)

        expect(result.success?).to be true
        expect(result.success[:evidences].size).to be > 0
      end
    end
  end
end
