# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::Notices::IvlOeReverificationTrigger, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  it 'should be a container-ready operation' do
    expect(subject.respond_to?(:call)).to be_truthy
  end

  describe '#call' do
    let(:primary) { FactoryBot.create(:person, :with_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: primary) }

    context 'with invalid notice_type' do
      let(:params) { { family: double('Family'), notice_type: 'invalid_type' } }

      it 'returns a Failure result' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Failure)
        expect(result.failure).to eq('notice_type is invalid. It should be either oeg or oeq')
      end
    end

    context 'with missing family for oeg notice' do
      let(:params) { { notice_type: 'oeg' } }

      it 'returns a Failure result' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Failure)
        expect(result.failure).to eq('family is required for oeq or oeg notices')
      end
    end

    context 'with missing family for oeq notice' do
      let(:params) { { notice_type: 'oeq' } }

      it 'returns a Failure result' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Failure)
        expect(result.failure).to eq('family is required for oeq or oeg notices')
      end
    end

    context 'with valid parameters for oeg notice' do
      let(:params) { { family: family, notice_type: 'oeg' } }

      it 'returns a Success result' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Success)
        expect(result.success).to eq("Event published successfully: events.individual.notices.expired_consent_during_reverification")
      end
    end

    context 'with valid parameters for oeq notice' do
      let(:params) { { family: family, notice_type: 'oeq' } }

      it 'returns a Success result' do
        result = subject.call(params)
        expect(result).to be_a(Dry::Monads::Success)
        expect(result.success).to eq("Event published successfully: events.individual.notices.qhp_eligible_on_reverification")
      end
    end
  end
end
