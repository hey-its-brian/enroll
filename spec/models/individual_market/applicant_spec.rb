# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Applicant, type: :model do
  let(:application)   { FactoryBot.create(:individual_market_application) }
  let(:family_member) { application.family.family_members.first }
  let(:person)        { family_member.person }
  let(:applicant) do
    FactoryBot.create(
      :individual_market_applicant,
      :with_person_name,
      :with_demographics,
      :with_eligibilities,
      application: application,
      family_member_id: family_member.id,
      person_id: person.id
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
  end

  describe 'fields' do
    it { is_expected.to have_field(:family_member_id).of_type(BSON::ObjectId) }
    it { is_expected.to have_field(:person_id).of_type(BSON::ObjectId) }
    it { is_expected.to have_field(:is_primary_applicant).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:address_same_as_primary).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:is_applying_coverage).of_type(Mongoid::Boolean) }
    it { is_expected.to have_field(:is_homeless).of_type(Mongoid::Boolean) }
  end

  describe '#family_member' do
    it 'returns the associated family member' do
      expect(applicant.family_member).to eq(family_member)
    end
  end

  describe '#person' do
    it 'returns the associated person' do
      expect(applicant.person).to eq(person)
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

  describe 'validations' do
    context 'when eligibilities have duplicate types' do
      it 'returns error message' do
        applicant.eligibilities << FactoryBot.build(:individual_market_eligibility)
        expect(applicant).not_to be_valid
        expect(applicant.errors[:eligibilities]).to include('cannot have duplicate eligibilities types')
      end
    end
  end
end
