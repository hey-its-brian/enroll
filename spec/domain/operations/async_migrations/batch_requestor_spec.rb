# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::BatchRequestor, dbclean: :after_each do
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

  describe '#initialize_logger' do
    context 'when logger is initialized successfully' do
      let(:logger) { double('Logger') }

      it 'returns a success monad containing the logger' do
        allow(Logger).to receive(:new).and_return(logger)
        result = subject.send(:initialize_logger)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq(logger)
      end
    end

    context 'when there is an error initializing logger' do
      it 'returns a failure monad containing an error message' do
        allow(Logger).to receive(:new).and_raise(StandardError.new('Error'))
        result = subject.send(:initialize_logger)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq('Error initializing logger: Error')
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

  describe '#fetch_batch_query' do
    context 'when query exists' do
      it 'returns a success monad containing the query' do
        result = subject.send(:fetch_batch_query, params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq(::Family.only(:_id))
      end
    end
  end

  context 'when query does not exist' do
    it 'returns a failure monad containing an error message' do
      params[:data_source] = '::NonExistentModel'
      result = subject.send(:fetch_batch_query, params)
      expect(result).to be_a(Dry::Monads::Result::Failure)
      expect(result.failure).to eq('query not found for string: ::NonExistentModel. A string-to-class mapping must be present in ::Operations::AsyncMigrations::Mappings::MODEL_MAP.')
    end
  end

  describe '#initiate_batch_requests' do
    let(:model_class) { double('ModelClass', count: 200, collection: double) }

    context 'when batch requests are initiated successfully' do
      it 'returns a success monad containing a success message' do
        result = subject.send(:initiate_batch_requests, model_class, params)
        msg = "Requested migration batches with params"
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to match(msg)
      end
    end

    context 'when there is an error initiating batch requests' do
      it 'returns a failure monad containing an error message' do
        allow(subject).to receive(:build_event).and_raise(StandardError.new('Error'))
        result = subject.send(:initiate_batch_requests, model_class, params)
        msg = "Error initiating batch request with params"
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to match(msg)
      end
    end
  end

  describe '#build_event' do
    it 'returns a success monad containing the event' do
      result = subject.send(:build_event, 0, params)
      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.success).to eq(mocked_event)
    end
  end
end
