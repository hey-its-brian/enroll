# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Demographics, type: :model do
  let(:applicant)     { FactoryBot.build(:individual_market_applicant, :dependent) }
  let(:demographics)  { FactoryBot.build(:individual_market_demographics, applicant: applicant) }

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
          demographics.encrypted_ssn = '123-45-6789'
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
          demographics.encrypted_ssn = '123-45-6789'
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
          demographics.encrypted_ssn = '123-45-6789'
        end

        it 'is valid' do
          expect(demographics.valid?).to be true
        end
      end

      context 'when no_ssn is nil' do
        before do
          demographics.no_ssn = nil
          demographics.encrypted_ssn = '123-45-6789'
        end

        it 'is valid' do
          expect(demographics.valid?).to be false
          expect(demographics.errors[:no_ssn]).to include('is not included in the list')
        end
      end
    end
  end
end
