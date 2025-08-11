# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Eligibilities::V3::IndividualMarket::VerificationRequests, type: :model, dbclean: :after_each do

  before :all do
    DatabaseCleaner.clean
  end

  let(:application) { FactoryBot.create(:financial_assistance_application) }
  let(:subject) { described_class.new }
  let(:application_entity_result) { Dry::Monads::Result::Success.new("application entity") }
  let(:ssa_vlp_result) { Dry::Monads::Result::Success.new("ssa vlp verification processed") }

  describe '#call' do
    context 'with valid application' do
      let(:build_payload_double) { double(call: application_entity_result) }
      let(:ssa_verification_double) { double(call: ssa_vlp_result) }

      before do
        allow(Operations::Fdsh::BuildAndValidateApplicationPayload).to receive(:new).and_return(build_payload_double)
        allow(Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification).to receive(:new).and_return(ssa_verification_double)
      end

      it 'returns success with the application' do
        result = subject.call(application: application)
        expect(result).to be_success
        expect(result.value!).to eq(application)
      end

      it 'calls the BuildAndValidateApplicationPayload operation' do
        expect(build_payload_double).to receive(:call).with(application).and_return(application_entity_result)
        subject.call(application: application)
      end

      it 'calls the SsaVlpVerification operation' do
        expect(ssa_verification_double).to receive(:call).with(entity_result: application_entity_result,
                                                               application: application,
                                                               call_type: 'application_determination').and_return(ssa_vlp_result)
        subject.call(application: application)
      end
    end

    context 'with invalid application type' do
      let(:invalid_application) { Object.new }
      let(:ssa_verification_double) { double(call: ssa_vlp_result) }

      before do
        allow(Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification).to receive(:new).and_return(ssa_verification_double)
      end

      it 'returns failure with error message' do
        result = subject.call(application: invalid_application)
        expect(result).to be_failure
        expect(result.failure).to include("Invalid application type")
      end

      it 'does not call verification services' do
        expect(ssa_verification_double).not_to receive(:call)
        subject.call(application: invalid_application)
      end
    end
  end
end
