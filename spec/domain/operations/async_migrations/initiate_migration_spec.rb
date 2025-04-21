# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::InitiateMigration, dbclean: :after_each do
  let(:subject) { described_class.new }
  let(:data_source) { 'families_with_id' }
  let(:migration_handler_name) { '::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility' }
  let(:batch_size) { 100 }
  let(:params) do
    {
      data_source: data_source,
      migration_handler_name: migration_handler_name,
      batch_size: batch_size
    }
  end
  let(:mocked_event) { double(publish: true) }

  before do
    allow(EventSource::Event).to receive(:new).and_return(mocked_event)
  end

  describe '#call' do
    context 'when params are valid' do
      it 'returns a success monad' do
        expect(subject.call(params)).to be_a(Dry::Monads::Result::Success)
      end
    end

    context 'when params are not valid' do
      it 'returns a failure monad' do
        expect(subject.call({})).to be_a(Dry::Monads::Result::Failure)
      end
    end
  end

  describe '#validate' do
    context 'when params are valid' do
      it 'returns a success monad containing the params' do
        result = subject.send(:validate, params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq(params)
      end
    end

    context 'when params are not valid' do
      context 'when params is not a hash' do
        it 'returns a failure monad with error message' do
          result = subject.send(:validate, [])
          expect(result).to be_a(Dry::Monads::Result::Failure)
          expect(result.failure).to eq('Params must be a hash')
        end
      end

      context 'when data_source is not a string' do
        it 'returns a failure monad with error message' do
          result = subject.send(:validate, params.merge(data_source: 1))
          expect(result).to be_a(Dry::Monads::Result::Failure)
          expect(result.failure).to eq('Data source must be a string')
        end
      end

      context 'when migration_handler_name is not a string' do
        it 'returns a failure monad with error message' do
          result = subject.send(:validate, params.merge(migration_handler_name: 1))
          expect(result).to be_a(Dry::Monads::Result::Failure)
          expect(result.failure).to eq('Event handler name must be a string')
        end
      end

      context 'when batch_size is not an integer' do
        it 'returns a failure monad with error message' do
          result = subject.send(:validate, params.merge(batch_size: '100'))
          expect(result).to be_a(Dry::Monads::Result::Failure)
          expect(result.failure).to eq('Batch size must be a number')
        end
      end
    end
  end

  describe '#build_event' do
    it 'returns a success monad containing the event' do
      result = subject.send(:build_event, params)
      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.success).to eq(mocked_event)
    end
  end

  describe '#initiate_migration' do
    context 'when event is published' do
      it 'returns a success monad with success message' do
        result = subject.send(:initiate_migration, mocked_event)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq('Successfully published event to initiate migration')
      end
    end

    context 'when event is not published' do
      let(:mocked_event) { double(publish: false) }

      it 'returns a failure monad' do
        result = subject.send(:initiate_migration, mocked_event)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq('Failed to publish event to initiate migration')
      end
    end
  end
end
