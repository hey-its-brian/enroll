# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactProfile::Email, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:contact_detail) { FactoryBot.create(:contact_profile_contact_detail, contactable: person) }
  let(:email) { FactoryBot.create(:contact_profile_email, contact_detail: contact_detail) }

  describe 'associations' do
    it 'is embedded in contact detail' do
      expect(email.contact_detail).to be_a(ContactProfile::ContactDetail)
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:work_email).of_type(String) }
    it { is_expected.to have_field(:personal_email).of_type(String) }
  end
end
