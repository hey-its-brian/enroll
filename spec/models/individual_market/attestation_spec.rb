# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Attestation, type: :model do
  let(:application) { FactoryBot.create(:individual_market_application) }
  let(:attestation) { FactoryBot.create(:individual_market_attestation, application: application) }

  describe 'fields' do
    it { is_expected.to have_field(:enrollment_terms).of_type(Mongoid::Boolean) }
  end

  describe 'associations' do
    it 'is embedded in an application' do
      expect(attestation.application).to eq(application)
      expect(attestation.application).to be_a(IndividualMarket::Application)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(attestation).to be_valid
    end
  end
end
