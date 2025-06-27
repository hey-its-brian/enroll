# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Demographics, type: :model do
  let(:applicant)     { FactoryBot.build(:individual_market_applicant, :dependent) }
  let(:demographics)  { FactoryBot.build(:individual_market_demographics, applicant: applicant) }
  let(:encrypted_ssn) { SymmetricEncryption.encrypt('123456789') }

  describe 'fields' do
    it { is_expected.to have_field(:encrypted_ssn).of_type(String) }
    it { is_expected.to have_field(:no_ssn).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:gender).of_type(String) }
    it { is_expected.to have_field(:dob).of_type(Date) }
    it { is_expected.to have_field(:is_incarcerated).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:indian_tribe_member).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:tribal_id).of_type(String) }
    it { is_expected.to have_field(:tribal_name).of_type(String) }
    it { is_expected.to have_field(:tribal_state).of_type(String) }
    it { is_expected.to have_field(:language_code).of_type(String) }
    it { is_expected.to have_field(:ethnicity).of_type(Array) }
    it { is_expected.to have_field(:race).of_type(Array) }
    it { is_expected.to have_field(:is_physically_disabled).of_type(Mongoid::Boolean) }
  end

  describe 'associations' do
    it 'is embedded in applicant' do
      expect(demographics.applicant).to eq(applicant)
      expect(demographics.applicant).to be_a(IndividualMarket::Applicant)
    end
  end

  describe 'validations' do
    describe '#no_ssn_or_encrypted_ssn' do
      context 'when:
        - no_ssn is true
        - encrypted_ssn is present' do

        before do
          demographics.no_ssn = true
          demographics.encrypted_ssn = encrypted_ssn
        end

        it 'adds an error' do
          demographics.valid?
          expect(demographics.errors[:base]).to include('Only one of no_ssn or encrypted_ssn must be present')
        end
      end

      context 'when:
        - no_ssn is false
        - encrypted_ssn is blank' do

        before do
          demographics.no_ssn = false
          demographics.encrypted_ssn = nil
        end

        it 'adds an error' do
          demographics.valid?
          expect(demographics.errors[:base]).to include('One of no_ssn or encrypted_ssn must be present')
        end
      end

      context 'when:
        - no_ssn is true
        - encrypted_ssn is blank' do

        before do
          demographics.no_ssn = true
          demographics.encrypted_ssn = nil
        end

        it 'is valid' do
          expect(demographics.valid?).to be true
        end
      end

      context 'when:
        - no_ssn is false
        - encrypted_ssn is present' do

        before do
          demographics.no_ssn = false
          demographics.encrypted_ssn = encrypted_ssn
        end

        it 'is valid' do
          expect(demographics.valid?).to be true
        end
      end
    end

    describe 'validation for no_ssn' do
      context 'when no_ssn is true' do
        before do
          demographics.no_ssn = true
          demographics.encrypted_ssn = nil
        end

        it 'is valid' do
          expect(demographics.valid?).to be true
        end
      end

      context 'when no_ssn is false' do
        before do
          demographics.no_ssn = false
          demographics.encrypted_ssn = encrypted_ssn
        end

        it 'is valid' do
          expect(demographics.valid?).to be true
        end
      end

      context 'when no_ssn is nil' do
        before do
          demographics.no_ssn = nil
          demographics.encrypted_ssn = encrypted_ssn
        end

        it 'is valid' do
          expect(demographics.valid?).to be false
          expect(demographics.errors[:no_ssn]).to include('is not included in the list')
        end
      end
    end
  end

  describe '#tribal_names' do
    let(:demographics) do
      FactoryBot.build(:individual_market_demographics, tribe_codes: tribe_codes, applicant: applicant)
    end

    before :each do
      allow(FinancialAssistanceRegistry[:featured_tribes_selection].setting(:featured_tribes).item).to receive(:to_h).and_return(
        { 'Maliseet' => 'HM', 'Passamaquoddy' => 'PD', 'Penobscot' => 'PE', 'Micmac' => 'AM', 'Other' => 'OT' }
      )
    end

    context 'when tribe_codes has nil or empty values' do
      let(:tribe_codes) { [nil, '', 'PD'] }

      it 'returns the names without raising errors' do
        expect(demographics.tribal_names).to eq('Passamaquoddy')
      end
    end

    context 'when tribe_codes has valid codes' do
      let(:tribe_codes) { ['AM', 'HM'] }

      it 'returns the names of the tribes' do
        expect(demographics.tribal_names).to eq('Micmac, Maliseet')
      end
    end
  end
end
