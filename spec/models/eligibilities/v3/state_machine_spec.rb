# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::StateMachine do
  let(:dummy_class) do
    Class.new do
      include Mongoid::Document
      include Eligibilities::V3::StateMachine

      # Explicitly define the STATES constant
      const_set(:STATES, [:initial, :verified, :rejected].freeze)

      field :current_state, type: Symbol
      embeds_many :state_histories, class_name: 'StateHistory'

      def initialize
        super
        self.current_state = :initial
      end
    end
  end

  let(:state_history_class) do
    Class.new do
      include Mongoid::Document

      field :from_state, type: Symbol
      field :to_state, type: Symbol
      field :event, type: Symbol
      field :transition_at, type: DateTime
      field :effective_on, type: DateTime
      field :reason, type: String
      field :comment, type: String
      field :metadata, type: Hash
    end
  end

  before do
    stub_const('DummyClass', dummy_class)
    stub_const('StateHistory', state_history_class)
  end

  describe 'state_transitions' do
    before do
      dummy_class.state_transitions do
        action :verify, from: [:initial], to: :verified
        action :reject, from: [:verified], to: :rejected
      end
    end

    let(:instance) { dummy_class.new }

    context 'predicate methods' do
      it 'defines predicate methods for each state' do
        expect(instance).to respond_to(:initial?)
        expect(instance).to respond_to(:verified?)
        expect(instance).to respond_to(:rejected?)
      end

      it 'returns true for the current state' do
        expect(instance.initial?).to be true
        expect(instance.verified?).to be false
        expect(instance.rejected?).to be false
      end
    end

    context 'guard methods' do
      it 'defines guard methods for actions' do
        expect(instance).to respond_to(:can_verify?)
        expect(instance).to respond_to(:can_reject?)
      end

      it 'returns true if the action can be triggered' do
        expect(instance.can_verify?).to be true
        expect(instance.can_reject?).to be false
      end
    end

    context 'state transitions' do
      it 'transitions to the next state when the action is triggered' do
        instance.verify
        expect(instance.current_state).to eq(:verified)
        expect(instance.state_histories.size).to eq(1)
        history = instance.state_histories.first
        expect(history.from_state).to eq(:initial)
        expect(history.to_state).to eq(:verified)
        expect(history.event).to eq(:verify)
        expect(history.transition_at).to be_present
        expect(history.effective_on).to be_present
      end

      it 'raises an error for invalid transitions' do
        expect { instance.reject }.to raise_error("Invalid transition from initial to rejected for action reject")
      end

      context 'when transitioning from :initial to another state' do
        let(:evidence_instances) do
          [
            Eligibilities::V3::Evidences::SocialSecurityNumberEvidence.new,
            Eligibilities::V3::Evidences::CitizenshipEvidence.new,
            Eligibilities::V3::Evidences::ImmigrationEvidence.new,
            Eligibilities::V3::Evidences::AmericanIndianEvidence.new,
            Eligibilities::V3::Evidences::AliveEvidence.new,
            FinancialAssistance::Evidences::IncomeEvidence.new,
            FinancialAssistance::Evidences::EsiMecEvidence.new,
            FinancialAssistance::Evidences::NonEsiMecEvidence.new,
            FinancialAssistance::Evidences::LocalMecEvidence.new
          ]
        end

        it "will not raise an error if the :from state is 'initial' and the :to state is 'unverified'" do
          evidence_instances.each do |evidence_instance|
            expect { evidence_instance.move_to_unverified }.to_not raise_error
          end
        end
      end
    end
  end
end