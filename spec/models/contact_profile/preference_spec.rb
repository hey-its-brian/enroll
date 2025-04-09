# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactProfile::Preference, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:contact_detail) { FactoryBot.create(:contact_profile_contact_detail, contactable: person) }
  let(:preference) { FactoryBot.create(:contact_profile_preference, contact_detail: contact_detail) }

  describe 'associations' do
    it 'is embedded in contact detail' do
      expect(preference.contact_detail).to be_a(ContactProfile::ContactDetail)
    end
  end

  describe 'fields' do
    it 'has contact methods' do
      expect(preference.contact_methods).to eq(%w[email mail text])
    end

    it 'has a language preference' do
      expect(preference.language_preference).to eq('English')
    end
  end

  describe 'validations' do
    context 'with valid attributes' do
      it 'is valid' do
        expect(preference).to be_valid
      end
    end

    context 'with invalid attributes' do
      it 'is invalid with an invalid contact method' do
        preference.contact_methods = ['invalid']
        preference.valid?
        expect(preference.errors[:contact_methods]).to include(
          'must be one or more of the following: email, mail, text'
        )
      end

      it 'is invalid without a language preference' do
        preference.language_preference = nil
        preference.valid?
        expect(preference.errors[:language_preference]).to include("can't be blank")
      end
    end
  end
end
