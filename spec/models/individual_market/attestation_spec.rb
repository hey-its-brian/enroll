# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Attestation, type: :model do
  let(:application) { FactoryBot.create(:individual_market_application, :with_primary) }
  let(:attestation) { FactoryBot.create(:individual_market_attestation, application: application) }

  describe 'fields' do
    it { is_expected.to have_field(:signer_role).of_type(String) }
    it { is_expected.to have_field(:signer_id).of_type(BSON::ObjectId) }
    it { is_expected.to have_field(:signed_at).of_type(DateTime) }
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

    describe 'validation of signer_role' do
      shared_examples_for 'validate signer_role' do |field_value, valid|
        context "when signer_role is #{field_value}" do
          before do
            attestation.signer_role = field_value
          end

          it "returns #{valid}" do
            expect(attestation.valid?).to eq(valid)
          end

          it "does #{valid ? 'not' : nil} have errors" do
            attestation.valid?

            if valid
              expect(attestation.errors).to be_empty
            else
              expect(attestation.errors[:signer_role]).to include('is not included in the list')
            end
          end
        end
      end

      context 'signer_role validation' do
        it_behaves_like 'validate signer_role', 'admin', true
        it_behaves_like 'validate signer_role', 'assister', true
        it_behaves_like 'validate signer_role', 'broker', true
        it_behaves_like 'validate signer_role', 'consumer', true
        it_behaves_like 'validate signer_role', 'anything', false
      end
    end
  end
end
