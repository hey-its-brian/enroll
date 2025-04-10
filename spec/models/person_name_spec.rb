# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PersonName, type: :model do
  let(:person_name) { FactoryBot.build(:person_name) }

  describe 'fields' do
    it { is_expected.to have_field(:given_name).of_type(String) }
    it { is_expected.to have_field(:middle_name).of_type(String) }
    it { is_expected.to have_field(:family_name).of_type(String) }
    it { is_expected.to have_field(:name_sfx).of_type(String) }
    it { is_expected.to have_field(:name_pfx).of_type(String) }
    it { is_expected.to have_field(:alternate_name).of_type(String) }
  end

  describe 'associations' do
    context 'when person_nameable is an applicant' do
      let(:person_name)     { FactoryBot.build(:person_name, person_nameable: person_nameable) }
      let(:person_nameable) { FactoryBot.build(:individual_market_applicant, :dependent) }

      it 'is embedded in applicant' do
        expect(person_name.person_nameable).to be_a(IndividualMarket::Applicant)
        expect(person_name.person_nameable).to eq(person_nameable)
      end
    end
  end

  describe '#full_name' do
    it 'returns the full name with all components' do
      expect(person_name.full_name).to eq('Mr. Johnny A. Doe Jr.')
    end

    it 'returns the full name without missing components' do
      person_name.middle_name = nil
      expect(person_name.full_name).to eq('Mr. Johnny Doe Jr.')
    end
  end
end
