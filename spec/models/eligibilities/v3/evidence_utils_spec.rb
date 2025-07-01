# frozen_string_literal: true

require 'rails_helper'

# Dummy class for testing EvidenceUtils module
class DummyEvidence
  include Mongoid::Document
  include Mongoid::Timestamps
  include Eligibilities::V3::EvidenceUtils

  field :current_state, type: Symbol
  field :is_satisfied, type: Boolean, default: false
end

RSpec.describe Eligibilities::V3::EvidenceUtils do
  let(:dummy_evidence) { DummyEvidence.new current_state: :pending }
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
    it { expect(dummy_evidence).to respond_to(:verification_outstanding) }
    it { expect(dummy_evidence).to respond_to(:due_on) }
    it { expect(dummy_evidence).to respond_to(:external_service) }
    it { expect(dummy_evidence).to respond_to(:updated_by) }
    it { expect(dummy_evidence).to respond_to(:state_histories) }
    it { expect(dummy_evidence).to respond_to(:verification_histories) }
    it { expect(dummy_evidence).to respond_to(:request_results) }
    it { expect(dummy_evidence).to respond_to(:is_active) }
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

  describe 'for action permission check methods' do
    shared_examples_for 'check permission and transition' do |action, to_state|
      context "for #{action} action" do
        described_class::STATES.each do |state|
          context "when current_state is #{state}" do
            let(:state_histories) { spy('state_histories') }
            before do
              dummy_evidence.current_state = state
              allow(dummy_evidence).to receive(:state_histories).and_return(state_histories)
            end

            it "returns true for can_#{action}?" do
              if dummy_evidence.send("can_#{action}?")
                expect { dummy_evidence.send(action)}
                  .to change(dummy_evidence, :current_state).from(state).to(to_state)

                expect(dummy_evidence.state_histories).to have_received(:build).with(
                  transition_at: now,
                  from_state: state,
                  to_state: to_state,
                  event: action,
                  comment: nil,
                  effective_on: now,
                  reason: nil
                )
              else
                expect { dummy_evidence.send(action) }.to raise_error(RuntimeError, /Invalid transition from #{state}/i)
              end
            end
          end
        end
      end
    end

    it_behaves_like 'check permission and transition', :move_to_attested, :attested
    it_behaves_like 'check permission and transition', :move_to_rejected, :rejected
    it_behaves_like 'check permission and transition', :move_to_negative_response_received, :negative_response_received
    it_behaves_like 'check permission and transition', :move_to_unverified, :unverified
    it_behaves_like 'check permission and transition', :move_to_outstanding, :outstanding
    it_behaves_like 'check permission and transition', :move_to_verified, :verified
    it_behaves_like 'check permission and transition', :move_to_review, :review
    it_behaves_like 'check permission and transition', :move_to_pending, :pending
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

  describe "#mark_as_outstanding" do
    it "marks the evidence as outstanding and sets due_on" do
      dummy_evidence.mark_as_outstanding
      expect(dummy_evidence.verification_outstanding).to be true
      expect(dummy_evidence.is_satisfied).to be false
      expect(dummy_evidence.due_on).to eq(today + EnrollRegistry[:verification_document_due_in_days].item.days)
    end

    it "does not mark as outstanding if cannot move to outstanding" do
      allow(dummy_evidence).to receive(:can_move_to_outstanding?).and_return(false)
      expect { dummy_evidence.mark_as_outstanding }.not_to change(dummy_evidence, :verification_outstanding)
    end
  end

  describe "#mark_as_negative_response_received" do
    it "marks the evidence as negative_response_received" do
      dummy_evidence.mark_as_negative_response_received
      expect(dummy_evidence.negative_response_received?).to be true
      expect(dummy_evidence.is_satisfied).to be true
      expect(dummy_evidence.verification_outstanding).to be false
    end

    it "does not mark as negative_response_received if cannot move to negative_response_received" do
      allow(dummy_evidence).to receive(:can_move_to_negative_response_received?).and_return(false)
      expect { dummy_evidence.mark_as_negative_response_received }.not_to change(dummy_evidence, :negative_response_received?)
    end
  end

  describe "#mark_as_verified" do
    it "marks the evidence as verified" do
      dummy_evidence.mark_as_verified
      expect(dummy_evidence.verified?).to be true
      expect(dummy_evidence.is_satisfied).to be true
      expect(dummy_evidence.verification_outstanding).to be false
    end

    it "does not mark as verified if cannot move to verified" do
      allow(dummy_evidence).to receive(:can_move_to_verified?).and_return(false)
      expect { dummy_evidence.mark_as_verified }.not_to change(dummy_evidence, :verified?)
    end
  end

  describe "#mark_as_rejected" do
    it "marks the evidence as rejected" do
      dummy_evidence.mark_as_rejected
      expect(dummy_evidence.rejected?).to be true
      expect(dummy_evidence.is_satisfied).to be false
      expect(dummy_evidence.verification_outstanding).to be true
    end

    it "does not mark as rejected if cannot move to rejected" do
      allow(dummy_evidence).to receive(:can_move_to_rejected?).and_return(false)
      expect { dummy_evidence.mark_as_rejected }.not_to change(dummy_evidence, :rejected?)
    end
  end

  describe "#mark_as_review" do
    it "marks the evidence as review" do
      dummy_evidence.mark_as_review
      expect(dummy_evidence.review?).to be true
    end

    it "does not mark as review if cannot move to review" do
      allow(dummy_evidence).to receive(:can_move_to_review?).and_return(false)
      expect { dummy_evidence.mark_as_review }.not_to change(dummy_evidence, :review?)
    end
  end
end
