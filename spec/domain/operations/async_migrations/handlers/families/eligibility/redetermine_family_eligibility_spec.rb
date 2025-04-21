# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility, dbclean: :after_each do
  let(:subject) { described_class.new }
  let(:person) { create(:person, :with_consumer_role) }
  let(:family) do
    create(:family, :with_primary_family_member, :with_eligibility_determination,  person: person,
                                                                                   verification_status: 'outstanding', verification_due_date: TimeKeeper.date_of_record + 1.month)
  end
  let(:document_id) { family.id }
  let(:params) do
    {
      document_id: document_id.to_s,
      additional_params: {
        assistance_year: TimeKeeper.date_of_record.year,
        date_threshold: (TimeKeeper.date_of_record - 1.month).strftime('%Y-%m-%d')

      }
    }
  end
  let(:logger) { instance_double(Logger, info: true, error: true) }
  let(:mocked_event) { double(publish: true) }


  before do
    allow(Logger).to receive(:new).and_return(logger)
    allow(EventSource::Event).to receive(:new).and_return(mocked_event)
  end

  describe '#call' do
    context 'when params are valid' do
      before do
        @result = subject.call(params)
      end

      it 'returns a success monad' do
        expect(@result).to be_a(Dry::Monads::Result::Success)
      end

      it 'should update family eligibility status to not_enrolled' do
        family.reload
        expect(family.eligibility_determination.outstanding_verification_status).to eq('not_enrolled')
      end
    end

    context 'when params are not valid' do
      it 'returns a failure monad when params is not a hash' do
        result = subject.call([])
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq('Params must be a hash')
      end

      it 'returns a failure monad when document_id is invalid' do
        result = subject.call(document_id: 'invalid')
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to eq('Document id must be of valid BSON::ObjectId format')
      end
    end

    context 'when family is not found' do
      before do
        allow(::Family).to receive(:find).and_raise(Mongoid::Errors::DocumentNotFound.new(::Family, nil))
      end

      it 'returns a failure monad' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
        expect(result.failure).to include('::Family not found for document id')
      end
    end

    context 'when eligibility determination fails' do
      let(:person) { create(:person) }
      let(:family) { create(:family, :with_primary_family_member, person: person) }
      let(:document_id) { family.id }
      let(:params) do
        {
          document_id: document_id.to_s,
          additional_params: {
            assistance_year: TimeKeeper.date_of_record.year,
            date_threshold: (TimeKeeper.date_of_record - 1.month).strftime('%Y-%m-%d')
          }
        }
      end

      it 'returns a failure monad with the result because person has no consumer role' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
      end
    end

    context 'when no people are applying for coverage and have verified determination' do
      let(:person) { create(:person, :with_consumer_role) }
      let(:family) do
        create(:family, :with_primary_family_member, :with_eligibility_determination,  person: person,
                                                                                       verification_status: 'verified', verification_due_date: TimeKeeper.date_of_record + 1.month)
      end
      let(:document_id) { family.id }
      let(:params) do
        {
          document_id: document_id.to_s,
          additional_params: {
            assistance_year: TimeKeeper.date_of_record.year,
            date_threshold: (TimeKeeper.date_of_record - 1.month).strftime('%Y-%m-%d')
          }
        }
      end

      it 'returns a failure monad because all people are applying for coverage and no outstanding verification' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
      end
    end
  end

  describe 'determine_effective_date' do
    before do
      allow(subject).to receive(:initialize_logger).and_return(Dry::Monads::Result::Success.new(logger))
    end

    context 'with active health enrollments' do
      let!(:enrollment) { create(:hbx_enrollment, family: family, effective_on: TimeKeeper.date_of_record.beginning_of_year) }
      let!(:enrollment_scope) { [enrollment] }

      it 'uses the enrollment effective date' do
        result = subject.send(:determine_effective_date, family, params)
        expect(result).to eq(TimeKeeper.date_of_record.beginning_of_year)
      end
    end

    context 'with determined applications but no enrollments' do
      let!(:application) do
        create(:financial_assistance_application, effective_date: TimeKeeper.date_of_record.beginning_of_year,
                                                  family_id: family.id, aasm_state: 'determined')
      end

      it 'uses the application effective date' do
        result = subject.send(:determine_effective_date, family, params)
        expect(result).to eq(TimeKeeper.date_of_record.beginning_of_year)
      end
    end

    context 'with no enrollments or applications' do
      it 'uses the current date' do
        result = subject.send(:determine_effective_date, family, params)
        expect(result).to eq(TimeKeeper.date_of_record)
      end
    end
  end
end
