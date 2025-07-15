# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::GenerateApplication, dbclean: :after_each do
  subject { described_class.new }

  describe '#call' do
    context 'with invalid params' do
      context 'when family_id is missing or invalid' do
        let(:params) { { origin: :user, generation_reason: :manual } }

        it 'returns failure' do
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('family_id is expected in BSON format')
        end
      end

      context 'when origin is invalid' do
        let(:params) do
          {
            family_id: BSON::ObjectId.new,
            origin: 'invalid_origin',
            generation_reason: :manual
          }
        end

        it 'returns failure' do
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq(I18n.t('faa.errors.invalid_origin_source_error'))
        end
      end

      context 'when generation_reason is invalid' do
        let(:params) do
          {
            family_id: BSON::ObjectId.new,
            origin: :user,
            generation_reason: 'invalid_reason'
          }
        end

        it 'returns failure' do
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq(I18n.t('faa.errors.invalid_generation_reason_error'))
        end
      end
    end

    context 'with valid params' do
      let!(:hbx_profile)   { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
      let(:person) { FactoryBot.create(:person, :with_consumer_role, no_ssn: true) }
      let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let(:params) do
        {
          family_id: family.id,
          origin: :user,
          generation_reason: :manual
        }
      end

      let(:application_params) do
        {
          family_id: family.id,
          assistance_year: family.application_applicable_year,
          origin: :user,
          generation_reason: :manual,
          applicants: instance_of(Array)
        }
      end
      let(:existing_application) { FactoryBot.create(:individual_market_application, :initial, family_id: family.id) }

      let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
      let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }

      before do
        existing_application
        @result = subject.call(params)
      end

      it 'returns success' do
        expect(@result).to be_success
      end

      it 'builds an application' do
        expect(@result.success).to be_a(IndividualMarket::Application)
        expect(@result.success.family_id).to eq(family.id)
        expect(@result.success.persisted?).to be_falsey
      end

      it 'cancels previous applications' do
        expect(existing_application.reload.current_state).to eq(:cancelled)
      end
    end

    context 'when family lookup fails' do
      let(:family_id) { BSON::ObjectId.new }
      let(:params) do
        {
          family_id: family_id,
          origin: :user,
          generation_reason: :manual
        }
      end

      it 'returns the failure' do
        result = subject.call(params)
        expect(result).to be_failure
        expect(result.failure).to eq("Unable to find Family with ID #{family_id}.")
      end
    end
  end
end
