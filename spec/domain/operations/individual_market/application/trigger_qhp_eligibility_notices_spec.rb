# frozen_string_literal: true

require 'rails_helper'
require 'shared_contexts/dual_applications_with_eligible_family_setup'

RSpec.describe Operations::IndividualMarket::Application::TriggerQhpEligibilityNotices, dbclean: :after_each do
  include_context 'dual applications with eligible family setup'
  subject { described_class.new }

  let(:current_application) { create_individual_market_application }
  let(:params) { { application: current_application } }


  describe '#call' do
    context 'with valid parameters' do
      it 'returns success' do
        result = subject.call(params)
        expect(result).to be_success
      end

      context 'when application_entity is provided' do
        let(:current_application_entity) do
          Dry::Monads::Result::Success.new(
            Operations::IndividualMarket::Application::TransformToEntity.new.call(current_application).success
          )
        end
        let(:params_with_entity) { params.merge(application_entity: current_application_entity) }

        it 'returns success with application entity' do
          result = subject.call(params_with_entity)
          expect(result).to be_success
        end
      end
    end

    context 'with invalid parameters' do
      let(:invalid_params) { { application: 'invalid' } }

      it 'returns failure' do
        result = subject.call(invalid_params)
        expect(result).to be_failure
      end

      it 'returns error message for missing application' do
        result = subject.call(invalid_params)
        expect(result.failure).to include('Invalid Application')
      end
    end

    context 'with missing parameters' do
      let(:missing_params) { {} }

      it 'returns failure for missing application parameter' do
        result = subject.call(missing_params)
        expect(result).to be_failure
      end

      it 'returns error message for missing application' do
        result = subject.call(missing_params)
        expect(result.failure).to include('Missing Application')
      end
    end

    context 'with an application that is not determined' do
      let(:invalid_state) { :expired }

      before do
        current_application.expire
      end

      it 'returns an error' do
        result = subject.call(params)
        expect(result).to be_failure
        expect(result.failure).to include("Application is not in determined state: #{invalid_state}")
      end
    end
  end
end
