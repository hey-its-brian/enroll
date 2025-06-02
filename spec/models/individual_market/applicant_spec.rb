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
  end

  describe 'fields' do
    it { is_expected.to have_field(:family_member_id).of_type(BSON::ObjectId) }
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
