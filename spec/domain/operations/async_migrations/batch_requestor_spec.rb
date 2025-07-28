# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::BatchRequestor, dbclean: :after_each do
  describe '#for mongo object' do
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

  describe '#process_migration_batch_for_array' do
    let(:subject) { described_class.new }
    let(:data_source) { 'applications_with_aasm_state_and_hbx_ids' }
    let(:migration_handler_name) { 'migrate_fa_evidences' }
    let(:batch_size) { 25 }
    let(:params) do
      {
        data_source: data_source,
        migration_handler_name: migration_handler_name,
        batch_size: batch_size,
        additional_params: { aasm_state: "draft", data_type: 'Array'}
      }
    end
    let(:mocked_event) { double(publish: true) }

    before do
      allow(EventSource::Event).to receive(:new).and_return(mocked_event)
      allow(subject).to receive(:records_to_process).and_return((1..100).to_a)
    end

    # rubocop:disable Layout/LineLength
    context 'when processing batch for array' do
      it 'returns a success monad containing the processed batch' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.success).to eq(["------------------------------------------------------ \n Requested migration batches with params: {:data_source=>\"applications_with_aasm_state_and_hbx_ids\", :migration_handler_name=>\"migrate_fa_evidences\", :batch_size=>25, :additional_params=>{:aasm_state=>\"draft\", :data_type=>\"Array\"}, :records=>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25]}",
                                      "------------------------------------------------------ \n Requested migration batches with params: {:data_source=>\"applications_with_aasm_state_and_hbx_ids\", :migration_handler_name=>\"migrate_fa_evidences\", :batch_size=>25, :additional_params=>{:aasm_state=>\"draft\", :data_type=>\"Array\"}, :records=>[26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50]}",
                                      "------------------------------------------------------ \n Requested migration batches with params: {:data_source=>\"applications_with_aasm_state_and_hbx_ids\", :migration_handler_name=>\"migrate_fa_evidences\", :batch_size=>25, :additional_params=>{:aasm_state=>\"draft\", :data_type=>\"Array\"}, :records=>[51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75]}",
                                      "------------------------------------------------------ \n Requested migration batches with params: {:data_source=>\"applications_with_aasm_state_and_hbx_ids\", :migration_handler_name=>\"migrate_fa_evidences\", :batch_size=>25, :additional_params=>{:aasm_state=>\"draft\", :data_type=>\"Array\"}, :records=>[76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100]}"])
      end
    end
    # rubocop:enable Layout/LineLength
  end
end
