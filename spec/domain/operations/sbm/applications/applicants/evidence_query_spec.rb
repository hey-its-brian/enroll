# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Sbm::Applications::Applicants::EvidenceQuery, dbclean: :after_each do
  subject { described_class.new }

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  before :all do
    ENV['ENABLE_ALIVE_STATUS'] = 'true'
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = 'true'
    ENV['QHP_APPLICATION_IS_ENABLED'] = 'true'
    load Rails.root.join('config', 'initializers', 'enroll_registry.rb')
  end

  after :all do
    ENV['ENABLE_ALIVE_STATUS'] = nil
    ENV['LOCAL_MEC_EVIDENCE_IS_ENABLED'] = nil
    ENV['QHP_APPLICATION_IS_ENABLED'] = nil
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
  let(:alive_evidence) { FactoryBot.create(:alive_evidence, :pending, eligibility: ivl_eligibility) }

  before :each do
    alive_evidence
    family.assign_latest_application_gid
    family.save!
  end

  context 'invalid params' do
    it 'returns an error when family is missing' do
      params = {
        person_id: person.id,
        evidence_key: 'alive_evidence',
        eligibility_kind: 'individual_market_eligibility',
        application: faa_application,
        applicant: applicant
      }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Family is missing')
    end

    it 'returns an error when person_id is missing' do
      params = {
        family: family,
        evidence_key: 'alive_evidence',
        eligibility_kind: 'individual_market_eligibility',
        application: faa_application,
        applicant: applicant
      }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Person ID is missing')
    end

    it 'returns an error when evidence_key is missing' do
      params = {
        family: family,
        person_id: person.id,
        eligibility_kind: 'individual_market_eligibility',
        application: faa_application,
        applicant: applicant
      }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Evidence key is missing')
    end

    it 'returns an error when eligibility_kind is missing' do
      params = {
        family: family,
        person_id: person.id,
        evidence_key: 'alive_evidence',
        application: faa_application,
        applicant: applicant
      }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Eligibility kind is missing')
    end

    it 'returns an error when application is missing' do
      params = {
        family: family,
        person_id: person.id,
        evidence_key: 'alive_evidence',
        eligibility_kind: 'individual_market_eligibility',
        applicant: applicant
      }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Application is missing')
    end

    it 'returns an error when applicant is missing' do
      params = {
        family: family,
        person_id: person.id,
        evidence_key: 'alive_evidence',
        eligibility_kind: 'individual_market_eligibility',
        application: faa_application
      }
      result = subject.call(params)
      expect(result.failure?).to be true
      expect(result.failure).to eq('Applicant is missing')
    end
  end

  context 'valid params' do
    let(:valid_params) do
      {
        family: family,
        person_id: person.id,
        evidence_key: 'alive_evidence',
        eligibility_kind: 'individual_market_eligibility',
        application: faa_application,
        applicant: applicant
      }
    end

    it 'returns member and evidence for valid params' do
      result = subject.call(valid_params)

      expect(result.success?).to be true
      expect(result.success[:member]).to eq(applicant.family_member)
      expect(result.success[:evidence]).to be_an(Adapters::EvidenceAdapter)
      expect(result.success[:display_previous_evidences]).to be true
    end

    context 'when finding evidence state' do
      it 'returns evidence for existing evidence key' do
        result = subject.call(valid_params)

        expect(result.success?).to be true
        expect(result.success[:evidence].evidence_item_key).to eq(:alive_evidence)
      end

      it 'returns error when eligibility not found' do
        params = valid_params.merge(eligibility_kind: 'nonexistent_eligibility')
        result = subject.call(params)

        expect(result.failure?).to be true
        expect(result.failure).to include('not found for')
      end

      it 'returns error when evidence not found in eligibility' do
        params = valid_params.merge(evidence_key: 'nonexistent_evidence')
        result = subject.call(params)

        expect(result.failure?).to be true
        expect(result.failure).to include('Evidence')
        expect(result.failure).to include('not found under')
      end
    end

    context 'when finding inactive evidence' do
      let(:inactive_params) do
        valid_params.merge(inactive: 'true')
      end

      context 'when inactive verifications feature is enabled' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_inactive_verifications).and_return(true)
        end

        it 'returns inactive evidence when it exists' do
          result = subject.call(inactive_params)

          expect(result.success?).to be true
          expect(result.success[:evidence]).to be_an(Adapters::EvidenceAdapter)
        end

        it 'returns error when inactive evidence not found' do
          params = inactive_params.merge(evidence_key: 'nonexistent_evidence')
          result = subject.call(params)

          expect(result.failure?).to be true
          expect(result.failure).to include('not found for')
        end
      end

      context 'when inactive verifications feature is disabled' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_inactive_verifications).and_return(false)
        end

        it 'returns error even when evidence exists' do
          result = subject.call(inactive_params)

          expect(result.failure?).to be true
          expect(result.failure).to eq('Inactive evidence display is not enabled')
        end
      end
    end
  end
end
