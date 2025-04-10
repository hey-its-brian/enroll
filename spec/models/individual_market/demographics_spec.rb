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
end
