# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Applicant::Build, dbclean: :after_each do
  subject { described_class.new }

  describe '#call' do
    context 'with valid params' do
      let(:valid_params) do
        {
          family_member_id: BSON::ObjectId.new,
          is_primary_applicant: true,
          address_same_as_primary: false,

          person_name: {
            given_name: 'John',
            family_name: 'Doe'
          },
          demographics: {
            dob: Date.new(1980, 1, 1),
            gender: 'male'
          },
          eligibilities: [
            {key: :medicaid, title: 'Medicaid'}
          ],
          is_applying_coverage: true
        }
      end


      let(:result) { subject.call(params: valid_params) }

      it 'should be success' do
        expect(result.success?).to be_truthy
      end

      it 'should build applicant entity object' do
        expect(result.success).to be_a ::Entities::IndividualMarket::Applicant
      end

    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          is_primary_applicant: true,
          address_same_as_primary: false,

          person_name: {
            given_name: 'John',
            family_name: 'Doe'
          },
          demographics: {
            dob: Date.new(1980, 1, 1),
            gender: 'male'
          },
          eligibilities: [
            {key: :medicaid, title: 'Medicaid'}
          ],
          is_applying_coverage: true
        }
      end

      let(:contract_errors) do
        {
          family_member_id: ["is missing", "must be BSON::ObjectId"]
        }
      end

      it 'returns failure with validation errors' do
        result = subject.call(params: invalid_params)
        expect(result).to be_failure
        expect(result.failure).to eq(contract_errors)
      end

      it 'does not create an Applicant entity' do
        expect(::Entities::IndividualMarket::Applicant).not_to receive(:new)
        subject.call(params: invalid_params)
      end
    end
  end
end
