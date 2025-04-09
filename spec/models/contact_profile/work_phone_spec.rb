# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactProfile::MobilePhone, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:contact_detail) { FactoryBot.create(:contact_profile_contact_detail, contactable: person) }
  let(:phone) { FactoryBot.create(:contact_profile_phone, contact_detail: contact_detail) }
  let(:work_phone) { FactoryBot.create(:contact_profile_work_phone, phone: phone) }

  describe 'associations' do
    it 'is embedded in phone' do
      expect(work_phone.phone).to be_a(ContactProfile::Phone)
    end
  end

  describe 'validations' do
    it 'is valid' do
      expect(work_phone).to be_valid
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:country_code).of_type(String) }
    it { is_expected.to have_field(:area_code).of_type(String) }
    it { is_expected.to have_field(:number).of_type(String) }
    it { is_expected.to have_field(:extension).of_type(String) }
    it { is_expected.to have_field(:primary).of_type(Mongoid::Boolean) }
  end
end
