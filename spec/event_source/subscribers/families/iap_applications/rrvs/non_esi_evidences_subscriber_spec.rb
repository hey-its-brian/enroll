# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Subscribers::Families::IapApplications::Rrvs::NonEsiEvidencesSubscriber, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  let(:subscriber) { described_class.new }
  let(:payload) { { application_hbx_id: 'test_hbx_id' } }
  let(:subscriber_logger) { instance_double(Logger) }

  # Mock the operation classes - separate instances for each operation
  let(:fa_request_determination_operation) { instance_double(FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::RequestDetermination) }
  let(:operations_request_determination_operation) { instance_double(Operations::Families::IapApplications::Rrvs::NonEsiEvidences::RequestDetermination) }

  before do
    allow(Logger).to receive(:new).and_return(subscriber_logger)
    allow(subscriber_logger).to receive(:info)
    allow(subscriber_logger).to receive(:error)

    # Mock the operation classes
    allow(FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::RequestDetermination).to receive(:new).and_return(fa_request_determination_operation)
    allow(Operations::Families::IapApplications::Rrvs::NonEsiEvidences::RequestDetermination).to receive(:new).and_return(operations_request_determination_operation)
  end

  describe '#determine_build_request' do
    context 'when qhp_application feature is enabled' do
      before do
        allow(subscriber).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      context 'when RequestDetermination operation succeeds' do
        let(:success_result) { Success('Operation completed successfully') }

        before do
          allow(fa_request_determination_operation).to receive(:call).with(payload).and_return(success_result)
        end

        it 'calls RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::RequestDetermination).to have_received(:new)
          expect(fa_request_determination_operation).to have_received(:call).with(payload)
        end

        it 'logs success message' do
          expect(subscriber_logger).to receive(:info).with('Rrvs::NonEsiEvidencesSubscriber, determine_verifications result: Success: Operation completed successfully')

          subscriber.send(:determine_build_request, payload, subscriber_logger)
        end

        it 'does not call Operations RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(Operations::Families::IapApplications::Rrvs::NonEsiEvidences::RequestDetermination).not_to have_received(:new)
        end
      end

      context 'when RequestDetermination operation fails' do
        let(:failure_result) { Failure('Operation failed with error') }

        before do
          allow(fa_request_determination_operation).to receive(:call).with(payload).and_return(failure_result)
        end

        it 'calls RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::RequestDetermination).to have_received(:new)
          expect(fa_request_determination_operation).to have_received(:call).with(payload)
        end

        it 'logs failure message' do
          expect(subscriber_logger).to receive(:info).with('Rrvs::NonEsiEvidencesSubscriber, determine_verifications result: Failure: Operation failed with error')

          subscriber.send(:determine_build_request, payload, subscriber_logger)
        end
      end

      context 'when RequestDetermination operation raises an exception' do
        let(:error_message) { 'Something went wrong' }
        let(:backtrace) { ['line1', 'line2', 'line3'] }
        let(:standard_error) { StandardError.new(error_message) }

        before do
          allow(standard_error).to receive(:backtrace).and_return(backtrace)
          allow(fa_request_determination_operation).to receive(:call).with(payload).and_raise(standard_error)
        end

        it 'rescues the exception and logs error' do
          expect(subscriber_logger).to receive(:error).with("Rrvs::NonEsiEvidencesSubscriber, error_message: #{error_message}, backtrace: #{backtrace}")

          expect { subscriber.send(:determine_build_request, payload, subscriber_logger) }.not_to raise_error
        end

        it 'still calls the RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::RequestDetermination).to have_received(:new)
          expect(fa_request_determination_operation).to have_received(:call).with(payload)
        end
      end
    end

    context 'when qhp_application feature is disabled' do
      before do
        allow(subscriber).to receive(:qhp_application_feature_enabled?).and_return(false)
      end

      context 'when RequestDetermination operation succeeds' do
        let(:success_result) { Success('Legacy operation completed successfully') }

        before do
          allow(operations_request_determination_operation).to receive(:call).with(payload).and_return(success_result)
        end

        it 'calls RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(Operations::Families::IapApplications::Rrvs::NonEsiEvidences::RequestDetermination).to have_received(:new)
          expect(operations_request_determination_operation).to have_received(:call).with(payload)
        end

        it 'logs success message' do
          expect(subscriber_logger).to receive(:info).with('Rrvs::NonEsiEvidencesSubscriber, determine_verifications result: Success: Legacy operation completed successfully')

          subscriber.send(:determine_build_request, payload, subscriber_logger)
        end

        it 'does not call FinancialAssistance RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(FinancialAssistance::Operations::Applications::Rrv::NonEsiEvidence::RequestDetermination).not_to have_received(:new)
        end
      end

      context 'when RequestDetermination operation fails' do
        let(:failure_result) { Failure('Legacy operation failed with error') }

        before do
          allow(operations_request_determination_operation).to receive(:call).with(payload).and_return(failure_result)
        end

        it 'calls RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(Operations::Families::IapApplications::Rrvs::NonEsiEvidences::RequestDetermination).to have_received(:new)
          expect(operations_request_determination_operation).to have_received(:call).with(payload)
        end

        it 'logs failure message' do
          expect(subscriber_logger).to receive(:info).with('Rrvs::NonEsiEvidencesSubscriber, determine_verifications result: Failure: Legacy operation failed with error')

          subscriber.send(:determine_build_request, payload, subscriber_logger)
        end
      end

      context 'when RequestDetermination operation raises an exception' do
        let(:error_message) { 'Legacy operation exception' }
        let(:backtrace) { ['legacy_line1', 'legacy_line2'] }
        let(:standard_error) { StandardError.new(error_message) }

        before do
          allow(standard_error).to receive(:backtrace).and_return(backtrace)
          allow(operations_request_determination_operation).to receive(:call).with(payload).and_raise(standard_error)
        end

        it 'rescues the exception and logs error' do
          expect(subscriber_logger).to receive(:error).with("Rrvs::NonEsiEvidencesSubscriber, error_message: #{error_message}, backtrace: #{backtrace}")

          expect { subscriber.send(:determine_build_request, payload, subscriber_logger) }.not_to raise_error
        end

        it 'still calls the RequestDetermination operation' do
          subscriber.send(:determine_build_request, payload, subscriber_logger)

          expect(Operations::Families::IapApplications::Rrvs::NonEsiEvidences::RequestDetermination).to have_received(:new)
          expect(operations_request_determination_operation).to have_received(:call).with(payload)
        end
      end
    end

    context 'edge cases' do
      before do
        allow(subscriber).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      context 'when payload is nil' do
        let(:payload) { nil }
        let(:success_result) { Success('Handled nil payload') }

        before do
          allow(fa_request_determination_operation).to receive(:call).with(nil).and_return(success_result)
        end

        it 'handles nil payload gracefully' do
          expect { subscriber.send(:determine_build_request, payload, subscriber_logger) }.not_to raise_error

          expect(fa_request_determination_operation).to have_received(:call).with(nil)
        end
      end

      context 'when payload is empty hash' do
        let(:payload) { {} }
        let(:failure_result) { Failure('Missing required parameters') }

        before do
          allow(fa_request_determination_operation).to receive(:call).with({}).and_return(failure_result)
        end

        it 'handles empty payload and logs failure' do
          expect(subscriber_logger).to receive(:info).with('Rrvs::NonEsiEvidencesSubscriber, determine_verifications result: Failure: Missing required parameters')

          subscriber.send(:determine_build_request, payload, subscriber_logger)
        end
      end
    end
  end

  describe '#subscriber_logger_for' do
    let(:event) { :test_event }
    let(:formatted_date) { TimeKeeper.date_of_record.strftime('%Y_%m_%d') }
    let(:expected_log_path) { "#{Rails.root}/log/#{event}_#{formatted_date}.log" }

    it 'creates a logger with the correct path' do
      expect(Logger).to receive(:new).with(expected_log_path)

      subscriber.send(:subscriber_logger_for, event)
    end

    it 'formats the date correctly' do
      allow(TimeKeeper).to receive(:date_of_record).and_return(Date.new(2023, 12, 25))
      expected_path = "#{Rails.root}/log/test_event_2023_12_25.log"

      expect(Logger).to receive(:new).with(expected_path)

      subscriber.send(:subscriber_logger_for, event)
    end
  end

  describe 'integration with ResourceRegistryHelper' do
    context 'when EnrollRegistry feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      end

      it 'returns true for qhp_application_feature_enabled?' do
        expect(subscriber.send(:qhp_application_feature_enabled?)).to be true
      end
    end

    context 'when EnrollRegistry feature is disabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
      end

      it 'returns false for qhp_application_feature_enabled?' do
        expect(subscriber.send(:qhp_application_feature_enabled?)).to be false
      end
    end
  end

  describe 'class inheritance and modules' do
    it 'includes ResourceRegistryHelper' do
      expect(described_class.included_modules).to include(ResourceRegistryHelper)
    end
  end
end
