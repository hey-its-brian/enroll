# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibilityUnconditionally, dbclean: :after_each do
  let(:subject) { described_class.new }
  let(:person) { create(:person, :with_consumer_role) }
  let(:family) do
    create(:family, :with_primary_family_member, :with_eligibility_determination,  person: person,
                                                                                   verification_status: 'outstanding', verification_due_date: TimeKeeper.date_of_record + 1.month)
  end
  let(:document_id) { family.id }
  let(:params) { { document_id: document_id.to_s } }
  let(:logger) { instance_double(Logger, info: true, error: true) }
  let(:mocked_event) { double(publish: true) }


  before do
    allow(family).to receive(:all_family_member_relations_defined).and_return(true)
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


      it 'returns a failure monad with the result because person has no consumer role' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Result::Failure)
      end
    end
  end
end
