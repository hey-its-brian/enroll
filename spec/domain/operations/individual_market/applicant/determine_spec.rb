# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Applicant::Determine, dbclean: :after_each do
  let(:application) { FactoryBot.create(:individual_market_application, :with_applicants) }
  let(:primary_applicant) { application.applicants.first }
  let(:dependent_applicant) { application.applicants.last }
  subject { described_class.new }

  describe '#call' do

    context 'with invalid params' do
      context 'when application is not correct type' do
        let(:params) { { application: nil, applicant: primary_applicant } }

        it 'returns failure' do
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('Invalid application type. Expected IndividualMarket::Application.')
        end
      end

      context 'when applicant is missing' do
        let(:params) { { application: application, applicant: nil } }

        it 'returns failure' do
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('Invalid applicant type. Expected IndividualMarket::Applicant.')
        end
      end

      context 'when applicant does not have an individual market eligibility' do
        let(:params) { { application: application, applicant: primary_applicant } }

        it 'returns failure' do
          primary_applicant.eligibilities = []
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq("Applicant #{primary_applicant.id} does not have an individual market eligibility")
        end
      end
    end

    context 'when application and applicant are valid' do
      let(:params) { { application: application, applicant: primary_applicant } }

      it 'returns success' do
        expect(subject.call(params)).to be_success
      end

      it 'builds determinations for primary applicant' do
        result = subject.call(params)
        expect(result.success).to eq(primary_applicant)
        expect(result.success.individual_market_eligibility.determinations.count).to eq 2
      end

    end
  end

  describe 'qhp eligibility' do
    let(:params) { { application: application, applicant: primary_applicant } }

    before do
      primary_applicant.demographics.citizen_status = 'us_citizen'
      primary_applicant.addresses << FactoryBot.create(:location_address, addressable: primary_applicant, kind: 'home')
    end

    it 'when all bases are satisfied' do
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination

      expect(qhp_determination.bases.where(basis_kind: 'applying_coverage').first.is_satisfied).to eq true
      expect(qhp_determination.bases.where(basis_kind: 'is_alive').first.is_satisfied).to eq true
      expect(qhp_determination.bases.where(basis_kind: 'state_resident').first.is_satisfied).to eq true
      expect(qhp_determination.bases.where(basis_kind: 'not_incarcerated').first.is_satisfied).to eq true
      expect(qhp_determination.bases.where(basis_kind: 'lawfully_present_in_us').first.is_satisfied).to eq true
      expect(qhp_determination.is_eligible).to eq true
    end

    it 'when applicant is incarcerated they should not be eligible' do
      primary_applicant.demographics.is_incarcerated = true
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination
      not_incarcerated_basis = qhp_determination.bases.where(basis_kind: 'not_incarcerated').first
      expect(qhp_determination.is_eligible).to eq false
      expect(not_incarcerated_basis.is_satisfied).to eq false
    end

    it 'when applicant is not applying for coverage they should not be eligible' do
      primary_applicant.is_applying_coverage = false
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination
      applying_coverage_basis = qhp_determination.bases.where(basis_kind: 'applying_coverage').first
      expect(qhp_determination.is_eligible).to eq false
      expect(applying_coverage_basis.is_satisfied).to eq false
    end

    it 'when applicant does not have an address they should not be eligible' do
      primary_applicant.addresses = []
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination
      applying_coverage_basis = qhp_determination.bases.where(basis_kind: 'state_resident').first
      expect(qhp_determination.is_eligible).to eq false
      expect(applying_coverage_basis.is_satisfied).to eq false
    end

    it 'when applicant is not a state resident they should not be eligible' do
      primary_applicant.addresses.destroy_all
      primary_applicant.addresses << FactoryBot.create(:location_address, addressable: primary_applicant, kind: 'home', state: 'NA')
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination
      state_resident_basis = qhp_determination.bases.where(basis_kind: 'state_resident').first
      expect(qhp_determination.is_eligible).to eq false
      expect(state_resident_basis.is_satisfied).to eq false
    end

    it 'when applicant is not a state resident but has an adult family member that is they should be eligible' do
      primary_applicant.addresses.destroy_all
      dependent_applicant.addresses << FactoryBot.create(:location_address, addressable: primary_applicant, kind: 'home', state: Settings.aca.state_abbreviation)
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination
      state_resident_basis = qhp_determination.bases.where(basis_kind: 'state_resident').first
      expect(qhp_determination.is_eligible).to eq true
      expect(state_resident_basis.is_satisfied).to eq true
    end

    it 'when applicant is not a state resident but has a child family member that is they should not be eligible' do
      primary_applicant.addresses = []
      dependent_applicant.demographics.dob = 17.years.ago
      dependent_applicant.addresses << FactoryBot.create(:location_address, addressable: dependent_applicant, kind: 'home', state: Settings.aca.state_abbreviation)
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination
      state_resident_basis = qhp_determination.bases.where(basis_kind: 'state_resident').first
      expect(qhp_determination.is_eligible).to eq false
      expect(state_resident_basis.is_satisfied).to eq false
    end

    it 'when the applicant has a ineligible citizen status they should not be eligible' do
      primary_applicant.demographics.citizen_status = 'not_lawfully_present_in_us'
      result = subject.call(params)
      qhp_determination = result.success.individual_market_eligibility.qhp_determination
      lawfully_present_basis = qhp_determination.bases.where(basis_kind: 'lawfully_present_in_us').first
      expect(qhp_determination.is_eligible).to eq false
      expect(lawfully_present_basis.is_satisfied).to eq false
    end
  end

  describe 'csr eligibility' do
    let(:params) { { application: application, applicant: primary_applicant } }

    it 'when is ai/na attested they should be eligible' do
      primary_applicant.demographics.indian_tribe_member = true
      result = subject.call(params)
      csr_determination = result.success.individual_market_eligibility.determinations.where(_type: 'Eligibilities::V3::Determinations::CsrDetermination').first
      native_american_basis = csr_determination.bases.where(basis_kind: 'ai_an_attested').first
      expect(csr_determination.is_eligible).to eq true
      expect(native_american_basis.is_satisfied).to eq true
    end

    it 'when is not ai/na attested they should not be eligible' do
      primary_applicant.demographics.indian_tribe_member = false
      result = subject.call(params)
      csr_determination = result.success.individual_market_eligibility.csr_determination
      expect(csr_determination.is_eligible).to eq false
    end
  end
end
