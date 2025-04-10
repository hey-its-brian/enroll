# frozen_string_literal: true

require 'rails_helper'

# Dummy class for testing EvidenceUtils module
class DummyEvidence
  include Mongoid::Document
  include Mongoid::Timestamps
  include Eligibilities::V3::EvidenceUtils

  field :current_state, type: Symbol
end

RSpec.describe Eligibilities::V3::EvidenceUtils do
  let(:dummy_evidence) { DummyEvidence.new }
  let(:today) { Date.today }
  let(:now) { Time.now }

  before do
    allow(Date).to receive(:today).and_return(today)
    allow(DateTime).to receive(:now).and_return(now)
  end

  describe 'validations' do
    context 'when current_state is not in STATES' do
      it 'is invalid' do
        dummy_evidence.current_state = :invalid_state
        expect(dummy_evidence).not_to be_valid
        expect(dummy_evidence.errors[:current_state]).to include('is not included in the list')
      end
    end

    context 'when current_state is in STATES' do
      it 'is valid' do
        dummy_evidence.current_state = :attested
        expect(dummy_evidence).to be_valid
      end
    end

    context 'when current_state is nil' do
      it 'is invalid' do
        dummy_evidence.current_state = nil
        expect(dummy_evidence).not_to be_valid
        expect(dummy_evidence.errors[:current_state]).to include('is not included in the list')
      end
    end
  end

  describe 'included fields and associations' do
    it { expect(dummy_evidence).to respond_to(:received_at) }
    it { expect(dummy_evidence).to respond_to(:verification_outstanding) }
    it { expect(dummy_evidence).to respond_to(:update_reason) }
    it { expect(dummy_evidence).to respond_to(:due_on) }
    it { expect(dummy_evidence).to respond_to(:external_service) }
    it { expect(dummy_evidence).to respond_to(:updated_by) }
    it { expect(dummy_evidence).to respond_to(:state_histories) }
    it { expect(dummy_evidence).to respond_to(:verification_histories) }
    it { expect(dummy_evidence).to respond_to(:request_results) }
  end

  describe 'for state predicate methods' do
    shared_examples_for 'state predicate methods' do |state|
      context "when current_state is #{state}" do
        before do
          dummy_evidence.current_state = state
        end

        it "returns true for #{state}?" do
          expect(dummy_evidence.send("#{state}?")).to be true
        end
      end
    end

    described_class::STATES.each do |state|
      include_examples 'state predicate methods', state
    end
  end

  describe 'for event permission check methods' do
    shared_examples_for 'permission check methods' do |event, allowed_states|
      context "for #{event} event" do
        described_class::STATES.each do |state|
          context "when current_state is #{state}" do
            before { dummy_evidence.current_state = state }

            if allowed_states.include?(state)
              it "returns true for may_#{event}?" do
                expect(dummy_evidence.send("may_#{event}?")).to be true
              end
            else
              it "returns false for may_#{event}?" do
                expect(dummy_evidence.send("may_#{event}?")).to be false
              end
            end
          end
        end
      end
    end

    described_class::STATE_TRANSITIONS.each do |event, transition|
      include_examples 'permission check methods', event, transition[:from]
    end
  end

  describe 'for state transition methods' do
    shared_examples_for 'state transition methods' do |event, from_states, to_state|
      context "for #{event} event" do
        from_states.each do |from_state|
          context "when current_state is #{from_state}" do
            before do
              dummy_evidence.current_state = from_state
            end

            it "changes state from #{from_state} to #{to_state}" do
              if from_state == to_state
                expect { dummy_evidence.send(event, 'test comment', 'test reason') }
                  .not_to change(dummy_evidence, :current_state)
              else
                expect { dummy_evidence.send(event, 'test comment', 'test reason') }
                  .to change(dummy_evidence, :current_state).from(from_state).to(to_state)
              end
            end

            it 'creates a state history record' do
              expect { dummy_evidence.send(event, 'test comment', 'test reason') }
                .to change { dummy_evidence.state_histories.size }.by(1)

              history = dummy_evidence.state_histories.last
              expect(history.from_state).to eq(from_state)
              expect(history.to_state).to eq(to_state)
              expect(history.effective_on).to eq(today)
              expect(history.transition_at).to eq(now)
              expect(history.event).to eq(event)
              expect(history.comment).to eq('test comment')
              expect(history.reason).to eq('test reason')
            end
          end
        end

        # Test state that's not in from_states
        invalid_states = described_class::STATES - from_states
        if invalid_states.any?
          context "when current_state is #{invalid_states.first}" do
            before { dummy_evidence.current_state = invalid_states.first }

            it 'raises an error when attempting invalid transition' do
              expect { dummy_evidence.send(event, 'test comment', 'test reason') }
                .to raise_error(ArgumentError, /Cannot #{event} from state:/)
            end
          end
        end
      end
    end

    described_class::STATE_TRANSITIONS.each do |event, transition|
      include_examples 'state transition methods', event, transition[:from], transition[:to]
    end
  end

  describe '#latest_state_history' do
    let(:oldest_history) { Eligibilities::V3::StateHistory.new(transition_at: 1.day.ago) }
    let(:newest_history) { Eligibilities::V3::StateHistory.new(transition_at: Time.now) }

    before do
      allow(dummy_evidence.state_histories).to receive(:newest).and_return(
        double(first: newest_history)
      )
    end

    it 'returns the most recent state history' do
      expect(dummy_evidence.latest_state_history).to eq(newest_history)
    end

    it 'memoizes the result' do
      dummy_evidence.latest_state_history
      dummy_evidence.latest_state_history
      expect(dummy_evidence.state_histories).to have_received(:newest).once
    end
  end
end
