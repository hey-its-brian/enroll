# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactProfile::Phone, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:contact_detail) { FactoryBot.create(:contact_profile_contact_detail, contactable: person) }
  let(:phone) do
    FactoryBot.create(
      :contact_profile_phone,
      :with_mobile_phone,
      :with_work_phone,
      contact_detail: contact_detail
    )
  end

  describe 'associations' do
    it 'is embedded in contact detail' do
      expect(phone.contact_detail).to eq(contact_detail)
    end

    it 'has one mobile phone' do
      expect(phone.mobile_phone).to be_a(ContactProfile::MobilePhone)
    end

    it 'has one work phone' do
      expect(phone.work_phone).to be_a(ContactProfile::WorkPhone)
    end
  end
end
