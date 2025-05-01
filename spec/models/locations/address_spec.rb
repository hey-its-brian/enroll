# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Locations::Address, type: :model do
  before :all do
    DatabaseCleaner.clean
  end

  let(:applicant) { FactoryBot.create(:individual_market_applicant) }
  let(:address) { FactoryBot.create(:location_address, addressable: applicant) }

  describe 'associations' do
    it 'is embedded in the addressable' do
      expect(address).to be_a(Locations::Address)
      expect(address.addressable).to eq(applicant)
    end
  end

  describe 'fields' do
    it { is_expected.to have_field(:kind).of_type(String) }
    it { is_expected.to have_field(:address_1).of_type(String) }
    it { is_expected.to have_field(:address_2).of_type(String) }
    it { is_expected.to have_field(:address_3).of_type(String) }
    it { is_expected.to have_field(:city).of_type(String) }
    it { is_expected.to have_field(:county).of_type(String) }
    it { is_expected.to have_field(:state).of_type(String) }
    it { is_expected.to have_field(:zip).of_type(String) }
    it { is_expected.to have_field(:country_name).of_type(String) }
    it { is_expected.to have_field(:quadrant).of_type(String) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:zip) }
    it { is_expected.to validate_presence_of(:kind) }
    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_inclusion_of(:kind).to_allow(Locations::Address::KINDS) }
    it { is_expected.to validate_presence_of(:address_1) }
    it { is_expected.to validate_presence_of(:city) }

    context 'zip validation' do
      it 'adds an error' do
        address = Locations::Address.new(zip: '123')
        address.valid?
        expect(address.errors[:zip]).to include(/should be in the form: 12345 or 12345-1234/)
      end

      it 'does not add an error for valid zip codes' do
        address.zip = '12345'
        address.valid?
        expect(address.errors[:zip]).to be_empty
      end

      it 'does not add an error for valid zip codes with 4 digit extension' do
        address.zip = '12345-6789'
        address.valid?
        expect(address.errors[:zip]).to be_empty
      end
    end
  end

  describe '#full_address' do
    it 'returns the full address as a string' do
      expect(address.full_address).to be_a(String)
      expect(address.full_address).not_to be_empty
    end
  end
end
