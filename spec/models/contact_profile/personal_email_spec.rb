# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactProfile::PersonalEmail, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:contact_detail) { FactoryBot.create(:contact_profile_contact_detail, contactable: person) }
  let(:email) { FactoryBot.create(:contact_profile_email, contact_detail: contact_detail) }
  let(:personal_email) { FactoryBot.create(:contact_profile_personal_email, email: email) }

  describe 'associations' do
    it 'is embedded in email' do
      expect(personal_email.email).to be_a(ContactProfile::Email)
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:address).of_type(String) }
  end
end
