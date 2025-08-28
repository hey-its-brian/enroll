# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::ConsumerRoles::CreateContactPreferences, type: :model do
  let(:operation) { described_class.new }
  let(:consumer_role) { instance_double('ConsumerRole') }
  let(:person) { instance_double('Person') }
  let(:attributes) { { preferred: 'email', email: 'test@example.com' } }
  let(:params) { { consumer_role: consumer_role, params: attributes } }

  before do
    allow(consumer_role).to receive(:person).and_return(person)
    allow(consumer_role).to receive(:skip_consumer_role_callbacks=)
    allow(person).to receive(:assign_attributes)
  end

  describe '#call' do
    context 'with valid params and successful save' do
      before do
        allow(person).to receive(:save).with(context: :enhanced_contact_preferences).and_return(true)
      end

      it 'returns Success' do
        result = operation.call(params)
        expect(result).to be_success
        expect(consumer_role).to have_received(:skip_consumer_role_callbacks=).with(true)
        expect(person).to have_received(:assign_attributes).with(attributes)
        expect(person).to have_received(:save).with(context: :enhanced_contact_preferences)
      end
    end

    context 'with invalid params' do
      it 'returns Failure(:invalid_params) if consumer_role missing' do
        result = operation.call({ params: attributes })
        expect(result).to be_failure
        expect(result.failure).to eq(:invalid_params)
      end

      it 'returns Failure(:invalid_params) if attributes missing' do
        result = operation.call({ consumer_role: consumer_role })
        expect(result).to be_failure
        expect(result.failure).to eq(:invalid_params)
      end
    end

    context 'when save fails' do
      let(:errors) { double('errors') }

      before do
        allow(person).to receive(:save).with(context: :enhanced_contact_preferences).and_return(false)
        allow(person).to receive(:errors).and_return(errors)
      end

      it 'returns Failure with errors' do
        result = operation.call(params)
        expect(result).to be_failure
        expect(result.failure).to eq(errors)
      end
    end
  end
end