# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Applicant, type: :model do
  let(:application)   { FactoryBot.create(:individual_market_application) }
  let(:family_member) { application.family.family_members.first }
  let(:applicant) do
    FactoryBot.build(
      :individual_market_applicant,
      :with_person_name,
      :with_demographics,
      :with_eligibilities,
      :with_home_address,
      :with_phone_number,
      :with_email,
      application: application,
      family_member_id: family_member.id,
      is_primary_applicant: true
    )
  end
  let(:dependent_applicant) do
    FactoryBot.create(
      :individual_market_applicant,
      :dependent,
      :with_person_name,
      :with_demographics,
      :with_eligibilities,
      application: application
    )
  end

  describe 'associations' do
    it 'embeds one person_name' do
      expect(applicant.person_name).to be_a(PersonName)
    end

    it 'embeds one demographics' do
      expect(applicant.demographics).to be_a(IndividualMarket::Demographics)
    end

    it 'embeds many eligibilities' do
      expect(applicant.eligibilities.first).to be_a(Eligibilities::V3::Eligibility)
    end

    it 'embeds many addresses' do
      expect(applicant.addresses.first).to be_a(Locations::Address)
    end

    it 'embeds many phones' do
      expect(applicant.phones.first).to be_a(Locations::Phone)
    end

    it 'embeds many emails' do
      expect(applicant.emails.first).to be_a(Locations::Email)
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:family_member_id).of_type(BSON::ObjectId) }
    it { is_expected.to have_field(:is_primary_applicant).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:address_same_as_primary).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:is_applying_coverage).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:is_homeless).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:is_temporarily_out_of_state).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:age_off_excluded).of_type(Mongoid::Boolean) }

    describe "#contact_method" do
      it { is_expected.to have_field(:contact_method).of_type(String) }

      describe "default value" do
        let(:new_applicant) { FactoryBot.build(:individual_market_applicant, application: application) }

        shared_examples "contact method behavior" do |contact_method_via_dropdown, enroll_sms_notifications, expected_method|
          before do
            allow(EnrollRegistry).to receive(:feature_enabled?).with(:contact_method_via_dropdown).and_return(contact_method_via_dropdown)
            allow(EnrollRegistry).to receive(:feature_enabled?).with(:enroll_sms_notifications).and_return(enroll_sms_notifications)
            load 'app/models/individual_market/applicant.rb'
          end

          it "defaults to '#{expected_method}'" do
            expect(new_applicant.contact_method).to eq(expected_method)
          end
        end

        context "when contact_method_via_dropdown feature is enabled" do
          it_behaves_like "contact method behavior", true, false, "Paper and Electronic communications"
        end

        context "when enroll_sms_notifications feature is enabled" do
          it_behaves_like "contact method behavior", false, true, "Paper and Electronic communications"
        end

        context "when both features are disabled" do
          it_behaves_like "contact method behavior", false, false, "Paper, Electronic and Text Message communications"
        end
      end
    end

    it { is_expected.to have_field(:language_preference).of_type(String) }
  end

  describe '#family_member' do
    it 'returns the associated family member' do
      expect(applicant.family_member).to eq(family_member)
    end
  end

  describe '#aptc_csr_eligibility' do
    it 'returns the associated aptc_csr_eligibility' do
      expect(applicant.aptc_csr_eligibility).to be_a(Eligibilities::V3::AptcCsrEligibility)
    end
  end

  describe '#individual_market_eligibility' do
    it 'returns the associated individual_market_eligibility' do
      expect(applicant.individual_market_eligibility).to be_a(Eligibilities::V3::IndividualMarketEligibility)
    end
  end

  describe 'build individual market eligibilities' do
    let(:individual_market_eligibility) { applicant.individual_market_eligibility }
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
          applicant.demographics.update_attributes(citizen_status: 'us_citizen')
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

        it 'returns nil' do
          applicant.update_attributes(is_applying_coverage: false)
          applicant.demographics.update_attributes(citizen_status: 'alien_lawfully_present')
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
          applicant.demographics.update_attributes(citizen_status: 'alien_lawfully_present')
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
        before { ai_an_evidence }

        it 'returns the existing evidence' do
          applicant.update_attributes(is_applying_coverage: false)
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
          applicant.update_attributes(is_applying_coverage: false)
          applicant.demographics.update_attributes(citizen_status: 'us_citizen')
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
        before { ai_an_evidence }

        it 'returns the existing ai_an_evidence' do
          applicant.demographics.update_attributes(indian_tribe_member: false)
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
          applicant.demographics.update_attributes(indian_tribe_member: true)
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
          applicant.demographics.update_attributes(indian_tribe_member: true)
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

        it 'returns nil' do
          applicant.demographics.update_attributes(indian_tribe_member: false)
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
        before { ssn_evidence }

        it 'returns the existing ssn_evidence' do
          applicant.demographics.update_attributes(no_ssn: '1', encrypted_ssn: nil)
          expect(result).to eq(ssn_evidence)
        end
      end

      context 'when:
        - ssn evidence is not present
        - encrypted_ssn is present
        ' do

        it 'builds a new ssn_evidence' do
          applicant.demographics.update_attributes(no_ssn: '1', encrypted_ssn: SymmetricEncryption.encrypt('123456789'))
          expect(result).to be_a(::Eligibilities::V3::Evidences::SocialSecurityNumberEvidence)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - ssn evidence is not present
        - encrypted_ssn is not present
        ' do

        it 'returns nil' do
          applicant.demographics.update_attributes(encrypted_ssn: nil, no_ssn: '1')
          expect(result).to be_nil
        end
      end
    end

    describe '#build_alive_evidence' do
      let(:alive_evidence) { FactoryBot.create(:alive_evidence, eligibility: individual_market_eligibility) }
      let(:result) { applicant.send(:build_alive_evidence) }

      context 'when:
        - alive evidence is present
        - consumer is applying for coverage
        - ssn evidence is present
        ' do

        before { alive_evidence }

        it 'returns the existing evidence' do
          expect(result).to eq(alive_evidence)
        end
      end

      context 'when:
        - alive evidence is present
        - consumer is applying for coverage
        - encrypted_ssn is not present
        ' do
        before { alive_evidence }

        it 'returns the existing evidence' do
          applicant.demographics.update_attributes(no_ssn: '1', encrypted_ssn: nil)
          expect(result).to eq(alive_evidence)
        end
      end

      context 'when:
        - alive evidence is present
        - consumer is not applying for coverage
        - encrypted_ssn is present
        ' do
        before { alive_evidence }

        it 'returns the existing evidence' do
          applicant.demographics.update_attributes(no_ssn: '1', encrypted_ssn: nil)
          expect(result).to eq(alive_evidence)
        end
      end

      context 'when:
        - alive evidence is present
        - consumer is not applying for coverage
        - encrypted_ssn is present
        ' do
        before { alive_evidence }

        it 'returns the existing evidence' do
          applicant.update_attributes(is_applying_coverage: false)
          expect(result).to eq(alive_evidence)
        end
      end

      context 'when:
        - alive evidence is not present
        - consumer is applying for coverage
        - consumer has an encrypted_ssn
        ' do

        it 'builds a new alive_evidence' do
          applicant.demographics.update_attributes(no_ssn: '1', encrypted_ssn: SymmetricEncryption.encrypt('123456789'))
          expect(result).to be_a(::Eligibilities::V3::Evidences::AliveEvidence)
          expect(result.eligibility).to eq(individual_market_eligibility)
          expect(result.eligibility.eligible).to eq(applicant)
        end
      end

      context 'when:
        - alive evidence is not present
        - consumer is applying for coverage
        - encrypted_ssn is not present
        ' do

        it 'returns nil' do
          applicant.demographics.update_attributes(encrypted_ssn: nil, no_ssn: '1')
          expect(result).to be_nil
        end
      end
    end
  end

  describe 'is_state_resident?' do
    before do
      applicant.addresses.destroy_all
    end

    it 'returns true when the applicant is homeless' do
      applicant.is_homeless = true
      expect(applicant.is_state_resident?).to eq(true)
    end

    it 'returns true when the applicant is temporarily out of state' do
      applicant.is_temporarily_out_of_state = true
      expect(applicant.is_state_resident?).to eq(true)
    end

    context 'when the applicant is not homeless or temporarily out of state' do
      it 'returns false if they have no addresses' do
        expect(applicant.is_state_resident?).to eq(false)
      end

      it 'returns false if they have an address in a different state' do
        applicant.addresses << FactoryBot.build(:location_address, state: 'CA')
        expect(applicant.is_state_resident?).to eq(false)
      end

      it 'returns true if they have an address in the same state' do
        applicant.addresses << FactoryBot.build(:location_address, state: Settings.aca.state_abbreviation)
        expect(applicant.is_state_resident?).to eq(true)
      end
    end
  end

  describe 'validations' do
    context 'when eligibilities have duplicate types' do
      it 'returns error message' do
        applicant.eligibilities << FactoryBot.build(:individual_market_eligibility)
        expect(applicant).not_to be_valid
        expect(applicant.errors[:eligibilities]).to include('cannot have duplicate eligibilities types')
      end
    end
  end

  describe '#relationship' do
    context 'when a relationship exists' do
      before do
        application.relationships.create!(
          source_id: dependent_applicant.id,
          relative_id: applicant.id,
          kind: 'spouse'
        )
      end

      it 'returns the relationship kind' do
        expect(dependent_applicant.relationship).to eq('spouse')
      end
    end

    context 'when no relationship exists' do
      it 'returns nil' do
        expect(dependent_applicant.relationship).to be_nil
      end
    end

    context 'when there is no primary applicant' do
      it 'returns nil' do
        application.applicants.where(is_primary_applicant: true).destroy_all
        expect(dependent_applicant.relationship).to be_nil
      end
    end
  end
end
