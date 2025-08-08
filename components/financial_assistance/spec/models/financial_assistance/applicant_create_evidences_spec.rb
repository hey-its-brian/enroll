# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Applicant, type: :model do
  before :all do
    DatabaseCleaner.clean
  end

  let(:application) { FactoryBot.create(:financial_assistance_application) }
  let(:applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      application: application,
      is_applying_coverage: applying_coverage,
      citizen_status: citizen_status,
      encrypted_ssn: encrypted_ssn,
      no_ssn: no_ssn,
      indian_tribe_member: indian_tribe_member
    )
  end
  let(:indian_tribe_member) { true }
  let(:encrypted_ssn) { SymmetricEncryption.encrypt('413496479') }
  let(:no_ssn) { '0' }
  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:individual_market_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:applying_coverage) { true }
  let(:citizen_status) { 'us_citizen' }

  describe '#build_aptc_csr_evidences & #build_individual_market_evidences' do
    context 'when eligibilities exists' do
      before :each do
        aptc_csr_eligibility
        individual_market_eligibility
      end

      it 'executes the methods without raising errors' do
        expect { applicant.send(:build_aptc_csr_evidences) }.not_to raise_error
        expect { applicant.send(:build_individual_market_evidences) }.not_to raise_error
      end
    end

    context 'when no eligibilities exist' do
      it 'raises an error' do
        expect { applicant.send(:build_aptc_csr_evidences) }.to raise_error(NoMethodError, /undefined method `esi_mec_evidence' for nil:NilClass/)
        expect { applicant.send(:build_individual_market_evidences) }.to raise_error(NoMethodError, /undefined method `alive_evidence' for nil:NilClass/)
      end
    end
  end

  describe 'for individual_market_eligibility' do
    before :each do
      aptc_csr_eligibility
      individual_market_eligibility
    end

    describe '#build_citizenship_evidence' do
      let(:citizenship_evidence) { FactoryBot.create(:citizenship_evidence, eligibility: individual_market_eligibility) }
      let(:result) { applicant.send(:build_citizenship_evidence) }

      context 'when:
        - citizenship evidence is present
        - consumer is applying for coverage
        - consumer is us citizen
        ' do

        before { citizenship_evidence }

        it 'returns the existing evidence' do
          expect(result).to eq(citizenship_evidence)
        end
      end

      context 'when:
        - citizenship evidence is present
        - consumer is applying for coverage
        - consumer is naturalized citizen
        ' do
        let(:citizen_status) { 'naturalized_citizen' }
        before { citizenship_evidence }

        it 'returns the existing evidence' do
          expect(result).to eq(citizenship_evidence)
        end
      end

      context 'when:
        - citizenship evidence is present
        - consumer is applying for coverage
        - consumer is not us citizen or naturalized citizen
        ' do

        let(:citizen_status) { 'alien_lawfully_present' }
        before { citizenship_evidence }

        it 'returns the existing evidence' do
          expect(result).to eq(citizenship_evidence)
        end
      end

      context 'when:
        - citizenship evidence is present
        - consumer is not applying for coverage
        - consumer is us citizen
        ' do
        let(:applying_coverage) { false }
        before { citizenship_evidence }

        it 'returns the existing evidence' do
          expect(result).to eq(citizenship_evidence)
        end
      end

      context 'when:
        - citizenship evidence is not present
        - consumer is applying for coverage
        - consumer is us citizen
        ' do

        it 'creates a new evidence' do
          expect(result).to be_a(::Eligibilities::V3::Evidences::CitizenshipEvidence)
          expect(result.current_state).to eq(:pending)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - citizenship evidence is not present
        - consumer is not applying for coverage
        - consumer is not us citizen or naturalized citizen
        ' do

        let(:applying_coverage) { false }
        let(:citizen_status) { 'alien_lawfully_present' }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end
    end

    describe '#build_immigration_evidence' do
      let(:ai_an_evidence) { FactoryBot.create(:immigration_evidence, eligibility: individual_market_eligibility) }
      let(:result) { applicant.send(:build_immigration_evidence) }

      context 'when:
        - immigration evidence is present
        - consumer is applying for coverage
        - consumer is alien_lawfully_present
        ' do
        let(:citizen_status) { 'alien_lawfully_present' }
        before { ai_an_evidence }

        it 'returns the the existing evidence' do
          expect(result).to eq(ai_an_evidence)
        end
      end

      context 'when:
        - immigration evidence is not present
        - consumer is applying for coverage
        - consumer is alien_lawfully_present
        ' do
        let(:citizen_status) { 'alien_lawfully_present' }

        it 'creates a new evidence' do
          expect(result).to be_a(::Eligibilities::V3::Evidences::ImmigrationEvidence)
          expect(result.current_state).to eq(:pending)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - immigration evidence is present
        - consumer is not applying for coverage
        - consumer is alien_lawfully_present
        ' do
        let(:applying_coverage) { false }
        let(:citizen_status) { 'alien_lawfully_present' }
        before { ai_an_evidence }

        it 'returns the existing evidence' do
          expect(result).to eq(ai_an_evidence)
        end
      end

      context 'when:
        - immigration evidence is present
        - consumer is applying for coverage
        - consumer is not alien_lawfully_present
        ' do
        before { ai_an_evidence }

        it 'returns the existing evidence' do
          expect(result).to eq(ai_an_evidence)
        end
      end

      context 'when:
        - immigration evidence is not present
        - consumer is not applying for coverage
        - consumer is not alien_lawfully_present
        ' do

        let(:applying_coverage) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end
    end

    describe '#build_american_indian_evidence' do
      let(:ai_an_evidence) { FactoryBot.create(:american_indian_evidence, eligibility: individual_market_eligibility) }
      let(:result) { applicant.send(:build_american_indian_evidence) }

      context 'when:
        - ai_an evidence is present
        - applicant is american indian or alaskan native
        ' do
        before { ai_an_evidence }

        it 'returns the existing ai_an_evidence' do
          expect(result).to eq(ai_an_evidence)
        end
      end

      context 'when:
        - ai_an evidence is present
        - applicant is not american indian or alaskan native
        ' do
        let(:indian_tribe_member) { false }
        before { ai_an_evidence }

        it 'returns the existing ai_an_evidence' do
          expect(result).to eq(ai_an_evidence)
        end
      end

      context 'when:
        - ai_an evidence is not present
        - applicant is american indian or alaskan native
        - ai_an_self_attestation feature is enabled
        ' do

        before { allow(EnrollRegistry).to receive(:feature_enabled?).with(:ai_an_self_attestation).and_return(true) }

        it 'builds a new ai_an_evidence' do
          expect(result).to be_a(::Eligibilities::V3::Evidences::AmericanIndianEvidence)
          expect(result.current_state).to eq(:attested)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - ai_an evidence is not present
        - applicant is american indian or alaskan native
        - ai_an_self_attestation feature is not enabled
        ' do

        it 'builds a new ai_an_evidence' do
          expect(result).to be_a(::Eligibilities::V3::Evidences::AmericanIndianEvidence)
          expect(result.current_state).to eq(:pending)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - ai_an evidence is not present
        - applicant is not american indian or alaskan native
        ' do
        let(:indian_tribe_member) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end
    end

    describe '#build_social_security_number_evidence' do
      let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, eligibility: individual_market_eligibility) }
      let(:result) { applicant.send(:build_social_security_number_evidence) }

      context 'when:
        - ssn evidence is present
        - encrypted_ssn is present
        ' do
        before { ssn_evidence }

        it 'returns the existing ssn_evidence' do
          expect(result).to eq(ssn_evidence)
        end
      end

      context 'when:
        - ssn evidence is present
        - encrypted_ssn is not present
        ' do
        let(:encrypted_ssn) { nil }
        let(:no_ssn) { '1' }
        before { ssn_evidence }

        it 'returns the existing ssn_evidence' do
          expect(result).to eq(ssn_evidence)
        end
      end

      context 'when:
        - ssn evidence is not present
        - encrypted_ssn is present
        ' do

        it 'builds a new ssn_evidence' do
          expect(result).to be_a(::Eligibilities::V3::Evidences::SocialSecurityNumberEvidence)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - ssn evidence is not present
        - encrypted_ssn is not present
        ' do
        let(:encrypted_ssn) { nil }
        let(:no_ssn) { '1' }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end
    end

    describe '#build_alive_evidence' do
      let(:alive_evidence) { FactoryBot.create(:alive_evidence, eligibility: individual_market_eligibility) }
      let(:result) { applicant.send(:build_alive_evidence) }

      context 'when:
        - alive evidence is present
        - is applying_coverage
        - encrypted_ssn is present
        ' do
        before { alive_evidence }

        it 'returns the existing alive_evidence' do
          expect(result).to eq(alive_evidence)
        end
      end

      context 'when:
        - alive evidence is present
        - is applying_coverage
        - encrypted_ssn is not present
        ' do
        let(:encrypted_ssn) { nil }
        let(:no_ssn) { '1' }
        before { alive_evidence }

        it 'returns the existing alive_evidence' do
          expect(result).to eq(alive_evidence)
        end
      end

      context 'when:
        - alive evidence is not present
        - is applying_coverage
        - encrypted_ssn is present
        ' do

        it 'builds a new alive_evidence' do
          expect(result).to be_a(::Eligibilities::V3::Evidences::AliveEvidence)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - alive evidence is not present
        - is not applying_coverage
        - encrypted_ssn is present
        ' do

        it 'returns nil' do
          applicant.update_attributes(is_applying_coverage: false)
          expect(result).to be_nil
        end
      end

      context 'when:
        - alive evidence is not present
        - encrypted_ssn is not present
        ' do
        let(:encrypted_ssn) { nil }
        let(:no_ssn) { '1' }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end
    end
  end

  describe 'for aptc_csr_eligibility' do
    before :each do
      aptc_csr_eligibility
      individual_market_eligibility
    end

    describe '#build_esi_mec_evi' do
      let(:feature_enabled) { true }
      let(:esi_mec_evidence) { FactoryBot.create(:esi_mec_evidence, eligibility: aptc_csr_eligibility) }
      let(:result) { applicant.send(:build_esi_mec_evi) }

      before :each do
        allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:esi_mec_determination).and_return(feature_enabled)
      end

      context 'when:
        - :esi_mec_determination feature is enabled
        - applicant is applying for coverage
        - there is an existing esi_mec_evidence
        ' do

        before { esi_mec_evidence }

        it 'returns the existing esi_mec_evidence' do
          expect(result).to eq(esi_mec_evidence)
        end
      end

      context 'when:
        - :esi_mec_determination feature is disabled
        - applicant is applying for coverage
        - there is an existing esi_mec_evidence
        ' do

        let(:feature_enabled) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end

      context 'when:
        - :esi_mec_determination feature is enabled
        - applicant is not applying for coverage
        - there is an existing esi_mec_evidence
        ' do

        let(:applying_coverage) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end

      context 'when:
        - :esi_mec_determination feature is enabled
        - applicant is applying for coverage
        - there is no existing esi_mec_evidence
        ' do

        it 'creates a new esi_mec_evidence' do
          expect(result).to be_a(::FinancialAssistance::Evidences::EsiMecEvidence)
          expect(result.eligibility).to eq(aptc_csr_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end
    end

    describe '#build_income_evi' do
      let(:feature_enabled) { true }
      let(:income_evidence) { FactoryBot.create(:income_evidence, eligibility: aptc_csr_eligibility) }
      let(:result) { applicant.send(:build_income_evi) }

      before :each do
        allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:ifsv_determination).and_return(feature_enabled)
      end

      context 'when applicant is applying_coverage' do
        context 'when:
          - :ifsv_determination feature is enabled
          - there is an existing income_evidence
          ' do

          before { income_evidence }

          it 'returns the existing income_evidence' do
            expect(result).to eq(income_evidence)
          end
        end

        context 'when:
          - :ifsv_determination feature is disabled
          - there is an existing income_evidence
          ' do

          let(:feature_enabled) { false }

          it 'returns nil' do
            expect(result).to be_nil
          end
        end

        context 'when:
          - :ifsv_determination feature is enabled
          - there is no existing income_evidence
          ' do

          it 'creates a new income_evidence' do
            expect(result).to be_a(::FinancialAssistance::Evidences::IncomeEvidence)
            expect(result.eligibility).to eq(aptc_csr_eligibility)
            expect(result.eligibility.eligible).to eq(applicant)
          end
        end
      end

      context 'when applicant is not applying_coverage' do
        let(:applying_coverage) { false }
        context 'when:
          - :ifsv_determination feature is enabled
          - there is an existing income_evidence
          ' do

          before { income_evidence }

          it 'returns the existing income_evidence' do
            expect(result).to eq(income_evidence)
          end
        end

        context 'when:
          - :ifsv_determination feature is disabled
          - there is an existing income_evidence
          ' do

          let(:feature_enabled) { false }

          it 'returns nil' do
            expect(result).to be_nil
          end
        end

        context 'when:
          - :ifsv_determination feature is enabled
          - there is no existing income_evidence
          ' do

          it 'creates a new income_evidence' do
            expect(result).to be_a(::FinancialAssistance::Evidences::IncomeEvidence)
            expect(result.eligibility).to eq(aptc_csr_eligibility)
            expect(result.eligibility.eligible).to eq(applicant)
          end
        end
      end
    end

    describe '#build_local_mec_evi' do
      let(:feature_enabled) { true }
      let(:local_mec_evidence) { FactoryBot.create(:local_mec_evidence, eligibility: aptc_csr_eligibility) }
      let(:result) { applicant.send(:build_local_mec_evi) }

      before :each do
        allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:mec_check).and_return(feature_enabled)
      end

      context 'when:
        - :mec_check feature is enabled
        - applicant is applying for coverage
        - there is an existing local_mec_evidence
        ' do

        before { local_mec_evidence }

        it 'returns the existing local_mec_evidence' do
          expect(result).to eq(local_mec_evidence)
        end
      end

      context 'when:
        - :mec_check feature is disabled
        - applicant is applying for coverage
        - there is an existing local_mec_evidence
        ' do

        let(:feature_enabled) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end

      context 'when:
        - :mec_check feature is enabled
        - applicant is not applying for coverage
        - there is an existing local_mec_evidence
        ' do

        let(:applying_coverage) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end

      context 'when:
        - :mec_check feature is enabled
        - applicant is applying for coverage
        - there is no existing local_mec_evidence
        ' do

        it 'creates a new local_mec_evidence' do
          expect(result).to be_a(::FinancialAssistance::Evidences::LocalMecEvidence)
          expect(result.eligibility).to eq(aptc_csr_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end
    end

    describe '#build_non_esi_mec_evi' do
      let(:feature_enabled) { true }
      let(:non_esi_mec_evidence) { FactoryBot.create(:non_esi_mec_evidence, eligibility: aptc_csr_eligibility) }
      let(:result) { applicant.send(:build_non_esi_mec_evi) }

      before :each do
        allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:non_esi_mec_determination).and_return(feature_enabled)
      end

      context 'when:
        - :non_esi_mec_determination feature is enabled
        - applicant is applying for coverage
        - there is an existing non_esi_mec_evidence
        ' do

        before { non_esi_mec_evidence }

        it 'returns the existing non_esi_mec_evidence' do
          expect(result).to eq(non_esi_mec_evidence)
        end
      end

      context 'when:
        - :non_esi_mec_determination feature is disabled
        - applicant is applying for coverage
        - there is an existing non_esi_mec_evidence
        ' do

        let(:feature_enabled) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end

      context 'when:
        - :non_esi_mec_determination feature is enabled
        - applicant is not applying for coverage
        - there is an existing non_esi_mec_evidence
        ' do

        let(:applying_coverage) { false }

        it 'returns nil' do
          expect(result).to be_nil
        end
      end

      context 'when:
        - :non_esi_mec_determination feature is enabled
        - applicant is applying for coverage
        - there is no existing non_esi_mec_evidence
        ' do

        it 'creates a new non_esi_mec_evidence' do
          expect(result).to be_a(::FinancialAssistance::Evidences::NonEsiMecEvidence)
          expect(result.eligibility).to eq(aptc_csr_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end
    end
  end

  describe '#build_aptc_eligibilities_evidences' do
    context 'when aptc_csr_eligibility is present' do
      before do
        aptc_csr_eligibility
        applicant.build_aptc_eligibilities_evidences
      end

      it 'builds the evidences for aptc_csr_eligibility' do
        expect(applicant.aptc_csr_eligibility).to eq(aptc_csr_eligibility)
        expect(applicant.aptc_csr_eligibility.evidences).not_to be_empty
      end
    end

    context 'when aptc_csr_eligibility is not present' do
      before do
        applicant.build_aptc_eligibilities_evidences
      end

      it 'builds aptc_csr_eligibility with evidences' do
        expect(applicant.aptc_csr_eligibility).to be_present
        expect(applicant.aptc_csr_eligibility.evidences).not_to be_empty
      end
    end
  end

  describe '#build_ivl_eligibility_with_evidences' do
    context 'when individual_market_eligibility is present' do
      before do
        individual_market_eligibility
        applicant.build_ivl_eligibility_with_evidences
      end

      it 'builds the evidences for individual_market_eligibility' do
        expect(applicant.individual_market_eligibility).to eq(individual_market_eligibility)
        expect(applicant.individual_market_eligibility.evidences).not_to be_empty
      end
    end

    context 'when individual_market_eligibility is not present' do
      before do
        applicant.build_ivl_eligibility_with_evidences
      end

      it 'builds individual_market_eligibility with evidences' do
        expect(applicant.individual_market_eligibility).to be_present
        expect(applicant.individual_market_eligibility.evidences).not_to be_empty
      end
    end
  end
end
