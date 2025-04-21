# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::BatchProcessor, dbclean: :after_each do
  let(:subject) { described_class.new }
  let(:data_source) { 'families_with_id' }
  let(:migration_handler_name) { '::Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility' }
  let(:skip) { 0 }
  let(:batch_size) { 5 }
  let(:params) do
    {
      data_source: data_source,
      migration_handler_name: migration_handler_name,
      skip: skip,
      batch_size: batch_size,
      additional_params: { assistance_year: TimeKeeper.date_of_record.year}
    }
  end
  let(:mocked_event) { double(publish: true) }

  before do
    allow(EventSource::Event).to receive(:new).and_return(mocked_event)
    create_list(:family, 10, :with_primary_family_member, :with_eligibility_determination,
                verification_status: "outstanding", verification_due_date: TimeKeeper.date_of_record,
                verification_document_status: "pending")
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
    context 'when model class exists' do
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

  describe '#process_migration_batch' do
    let(:model_class) { ::Family.only(:_id) }

    context 'when batch is processed successfully' do
      it 'returns a success monad containing a success message' do
        result = subject.send(:process_migration_batch, model_class, params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq("Published batch of events for migration using params: #{params}")
      end

      it 'publishes an event for each record in the batch' do
        expect(mocked_event).to receive(:publish).exactly(5).times
        subject.send(:process_migration_batch, model_class, params)
      end
    end

    context 'when there is an error processing the batch' do
      it 'returns a failure monad containing a failure message' do
        allow(subject).to receive(:build_event).and_raise(StandardError.new('Error'))
        result = subject.send(:process_migration_batch, model_class, params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq("Error processing batch request with params: #{params} - Error")
      end
    end
  end

  describe '#build_event' do
    it 'returns a success monad containing the event' do
      result = subject.send(:build_event, params[:migration_handler_name], '123abc', params[:additional_params])
      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.success).to eq(mocked_event)
    end
  end
end
