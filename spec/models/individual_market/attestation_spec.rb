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

    describe '#verify_signer_id_and_signed_at' do
      context 'when signer_role is one of SIGNER_ROLE_KINDS_WITH_SIGNER_ID' do
        context 'when signer_id and signed_at are present' do
          before do
            attestation.signer_role = 'admin'
            attestation.signer_id = BSON::ObjectId.new
            attestation.signed_at = DateTime.now
          end

          it 'is valid when signer_id and signed_at are present for a valid signer_role' do
            expect(attestation.valid?).to be true
          end
        end

        context 'when signer_id is present and signed_at is not present' do
          before do
            attestation.signer_role = 'admin'
            attestation.signer_id = BSON::ObjectId.new
            attestation.signed_at = nil
          end

          it 'is not valid' do
            expect(attestation.valid?).to be false
            expect(attestation.errors[:signed_at]).to include('must be present')
          end
        end

        context 'when signer_id is not present and signed_at is present' do
          before do
            attestation.signer_role = 'admin'
            attestation.signer_id = nil
            attestation.signed_at = DateTime.now
          end

          it 'is not valid' do
            expect(attestation.valid?).to be false
            expect(attestation.errors[:signer_id]).to include('must be present')
          end
        end

        context 'when both signer_id and signed_at are not present' do
          before do
            attestation.signer_role = 'admin'
            attestation.signer_id = nil
            attestation.signed_at = nil
          end

          it 'is not valid' do
            expect(attestation.valid?).to be false
            expect(attestation.errors[:signer_id]).to include('must be present')
            expect(attestation.errors[:signed_at]).to include('must be present')
          end
        end
      end

      context 'when signer_role is not one of SIGNER_ROLE_KINDS_WITH_SIGNER_ID' do
        context 'when signer_id and signed_at are present' do
          before do
            attestation.signer_role = 'system'
            attestation.signer_id = BSON::ObjectId.new
            attestation.signed_at = DateTime.now
          end

          it 'is not valid' do
            expect(attestation.valid?).to be false
            expect(attestation.errors[:signer_id]).to include('must not be present')
            expect(attestation.errors[:signed_at]).to include('must not be present')
          end
        end

        context 'when signer_id is present and signed_at is not present' do
          before do
            attestation.signer_role = 'system'
            attestation.signer_id = BSON::ObjectId.new
            attestation.signed_at = nil
          end

          it 'is not valid' do
            expect(attestation.valid?).to be false
            expect(attestation.errors[:signer_id]).to include('must not be present')
          end
        end

        context 'when signer_id is not present and signed_at is present' do
          before do
            attestation.signer_role = 'system'
            attestation.signer_id = nil
            attestation.signed_at = DateTime.now
          end

          it 'is not valid' do
            expect(attestation.valid?).to be false
            expect(attestation.errors[:signed_at]).to include('must not be present')
          end
        end

        context 'when both signer_id and signed_at are not present' do
          before do
            attestation.signer_role = 'system'
            attestation.signer_id = nil
            attestation.signed_at = nil
          end

          it 'is valid' do
            expect(attestation.valid?).to be true
            expect(attestation.errors).to be_empty
          end
        end
      end
    end
  end
end
