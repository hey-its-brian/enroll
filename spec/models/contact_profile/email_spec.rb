# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactProfile::Email, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:contact_detail) { FactoryBot.create(:contact_profile_contact_detail, contactable: person) }
  let(:email) do
    FactoryBot.create(
      :contact_profile_email,
      :with_personal_email,
      :with_work_email,
      contact_detail: contact_detail
    )
  end

  describe 'associations' do
    it 'is embedded in contact detail' do
      expect(email.contact_detail).to be_a(ContactProfile::ContactDetail)
    end

    it 'has one personal email' do
      expect(email.personal_email).to be_a(ContactProfile::PersonalEmail)
    end

    it 'has one work email' do
      expect(email.work_email).to be_a(ContactProfile::WorkEmail)
    end
  end
end
