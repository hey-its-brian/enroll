# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactProfile::ContactDetail, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:contact_detail) do
    FactoryBot.create(
      :contact_profile_contact_detail,
      :with_phone,
      :with_email,
      :with_preference,
      contactable: person
    )
  end

  describe 'associations' do
    it 'is embedded in person' do
      expect(contact_detail.contactable).to eq(person)
    end

    it 'has many phones' do
      expect(contact_detail.phones).to be_present
    end

    it 'has many emails' do
      expect(contact_detail.emails).to be_present
    end

    it 'has many preferences' do
      expect(contact_detail.preferences).to be_present
    end
  end
end
