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

  describe "#build_verification_history" do
    it "builds the verification history" do
      expect(dummy_evidence.build_verification_history("test_action", "test_reason", "test_user")).to be_a(Eligibilities::V3::VerificationHistory)
    end
  end

  describe 'state transition criteria' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:primary_applicant) { family.primary_applicant }
    let(:faa_application) do
      FactoryBot.create(
        :financial_assistance_application,
        family_id: family.id,
        aasm_state: 'determined',
        submitted_at: Time.now,
        assistance_year: TimeKeeper.date_of_record.year
      )
    end

    let(:applicant) do
      FactoryBot.create(
        :financial_assistance_applicant,
        family_member_id: primary_applicant.id,
        person_hbx_id: person.hbx_id,
        application: faa_application
      )
    end

    let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
    let(:citizenship_evidence) { FactoryBot.create(:citizenship_evidence, :rejected, eligibility: ivl_eligibility) }

    let(:faa_application1) do
      FactoryBot.create(
        :financial_assistance_application,
        family_id: family.id,
        aasm_state: 'determined',
        submitted_at: Time.now,
        assistance_year: TimeKeeper.date_of_record.year + 1,
        predecessor_id: faa_application.id
      )
    end

    let(:applicant1) do
      FactoryBot.create(
        :financial_assistance_applicant,
        family_member_id: primary_applicant.id,
        person_hbx_id: person.hbx_id,
        application: faa_application1
      )
    end
    let(:ivl_eligibility1) { FactoryBot.create(:individual_market_eligibility, eligible: applicant1) }
    let(:citizenship_evidence1) { FactoryBot.create(:citizenship_evidence, :rejected, eligibility: ivl_eligibility1) }


    before do
      citizenship_evidence
      citizenship_evidence1
    end

    describe "#fetch_family" do
      it "returns and memoizes the family" do
        expect(citizenship_evidence.fetch_family).to eq(family)
        expect(citizenship_evidence.fetch_family).to eq(family) # memoized
      end

      context "when eligibility chain is broken" do
        before { allow(citizenship_evidence).to receive(:eligibility).and_return(nil) }

        it "returns nil" do
          expect(citizenship_evidence.fetch_family).to be_nil
        end
      end
    end

    describe "#fetch_last_determined_application" do
      it "returns the last determined application" do
        expect(citizenship_evidence1.fetch_last_determined_application).to eq(faa_application)
      end

      context "when family is nil" do
        before { allow(citizenship_evidence1).to receive(:fetch_family).and_return(nil) }

        it "returns nil" do
          expect(citizenship_evidence1.fetch_last_determined_application).to be_nil
        end
      end
    end

    describe "#fetch_last_determined_applicant" do
      it "returns the matching applicant" do
        expect(citizenship_evidence1.fetch_last_determined_applicant).to eq(applicant)
      end

      context "when no family_member_id is available" do
        before do
          allow(applicant1).to receive(:family_member_id).and_return(nil)
        end

        it "returns nil" do
          expect(citizenship_evidence1.fetch_last_determined_applicant).to be_nil
        end
      end

      context "when application is nil" do
        before { allow(citizenship_evidence1).to receive(:fetch_last_determined_application).and_return(nil) }

        it "returns nil" do
          expect(citizenship_evidence1.fetch_last_determined_applicant).to be_nil
        end
      end
    end

    describe "#fetch_last_determined_evidence" do
      it "returns the matching evidence" do
        expect(citizenship_evidence1.fetch_last_determined_evidence).to eq(citizenship_evidence)
      end

      context "when applicant is nil" do
        before { allow(citizenship_evidence1).to receive(:fetch_last_determined_applicant).and_return(nil) }

        it "returns nil" do
          expect(citizenship_evidence1.fetch_last_determined_evidence).to be_nil
        end
      end

      context "when target_eligibility is nil" do
        before { applicant.eligibilities.delete_all }

        it "returns nil" do
          expect(citizenship_evidence1.fetch_last_determined_evidence).to be_nil
        end
      end
    end

    describe "#determine_outstanding_state" do
      context "when evidence is IVL, previous evidence is verified, and demographics changed" do
        before do
          citizenship_evidence.current_state = :verified
          citizenship_evidence.save
          allow(citizenship_evidence1).to receive(:demographics_changed?).and_return(true)
        end

        it "calls copied_verified" do
          citizenship_evidence1.determine_outstanding_state
          expect(citizenship_evidence1.current_state).to eq(:verified)
          expect(citizenship_evidence1.verification_histories.first.action).to eq('copied_verified')
        end
      end

      context "when evidence is not IVL" do
        let(:aptc_csr_eligibility)  { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
        let(:esi_evidence) { FactoryBot.create(:esi_mec_evidence, :pending, eligibility: aptc_csr_eligibility) }
        let(:aptc_csr_eligibility1)  { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant1) }
        let(:esi_evidence1) { FactoryBot.create(:esi_mec_evidence, :pending, eligibility: aptc_csr_eligibility1) }

        it "calls eligible_state" do
          esi_evidence1.determine_outstanding_state
          expect(esi_evidence1.current_state).to eq(:negative_response_received)
        end
      end

      context "when previous evidence is not verified" do
        it "calls eligible_state" do
          citizenship_evidence1.determine_outstanding_state
          expect(citizenship_evidence1.current_state).to eq(:negative_response_received)
        end
      end
    end

    describe "#demographics_changed?" do
      context "when previous applicant exists" do
        before do
          allow(applicant1).to receive(:name_changed?).with(applicant).and_return(false)
          allow(applicant1).to receive(:identity_info_changed?).with(applicant).and_return(false)
          allow(applicant1).to receive(:citizen_status_changed?).with(applicant).and_return(false)
          allow(applicant1).to receive(:indian_tribe_changed?).with(applicant).and_return(false)
        end

        it "returns false when no demographics changed" do
          expect(citizenship_evidence1.demographics_changed?).to be false
        end

        it "returns true when name changed" do
          allow(applicant1).to receive(:name_changed?).with(applicant).and_return(true)
          expect(citizenship_evidence1.demographics_changed?).to be true
        end

        it "returns true when identity info changed" do
          allow(applicant1).to receive(:identity_info_changed?).with(applicant).and_return(true)
          expect(citizenship_evidence1.demographics_changed?).to be true
        end

        it "returns true when citizen status changed" do
          allow(applicant1).to receive(:citizen_status_changed?).with(applicant).and_return(true)
          expect(citizenship_evidence1.demographics_changed?).to be true
        end

        it "returns true when indian tribe changed" do
          allow(applicant1).to receive(:indian_tribe_changed?).with(applicant).and_return(true)
          expect(citizenship_evidence1.demographics_changed?).to be true
        end
      end

      context "when previous applicant does not exist" do
        before { allow(citizenship_evidence1).to receive(:fetch_last_determined_applicant).and_return(nil) }

        it "returns false" do
          expect(citizenship_evidence1.demographics_changed?).to be false
        end
      end
    end

    describe "#copied_verified" do
      context "when can move to verified" do
        it "moves to verified and adds history" do
          citizenship_evidence1.copied_verified
          expect(citizenship_evidence1.current_state).to eq(:verified)
        end
      end

      context "when cannot move to verified" do
        before { allow(citizenship_evidence1).to receive(:can_move_to_verified?).and_return(false) }

        it "does not move to verified" do
          present_state = citizenship_evidence1.current_state
          citizenship_evidence1.copied_verified
          expect(citizenship_evidence1.current_state).to eq(present_state)
        end
      end
    end

    describe "#eligible_state" do
      before do
        citizenship_evidence1.current_state = :outstanding
        citizenship_evidence1.save
      end

      context "when ROP is in progress" do
        before do
          allow(citizenship_evidence1).to receive(:rop_in_progress?).and_return(true)
          allow(citizenship_evidence1).to receive(:can_move_to_rejected?).and_return(true)
        end

        it "calls rop_eligible_state" do
          citizenship_evidence1.eligible_state
          citizenship_evidence1.save
          expect(citizenship_evidence1.current_state).to eq(citizenship_evidence.current_state)
          expect(citizenship_evidence1.verification_histories.first.action).to eq('copied_rejected')
        end
      end

      context "when ROP is not in progress" do
        before { allow(citizenship_evidence1).to receive(:rop_in_progress?).and_return(false) }

        it "calls non_rop_eligible_state" do
          citizenship_evidence1.eligible_state
          citizenship_evidence1.save
          expect(citizenship_evidence1.current_state).to eq(:negative_response_received)
        end
      end
    end

    describe "#rop_in_progress?" do
      context "when previous evidence exists with valid ROP state and future due date" do
        before do
          citizenship_evidence.current_state = :review
          citizenship_evidence.due_on = today + 10.days
          citizenship_evidence.save
        end

        it "returns true" do
          expect(citizenship_evidence1.rop_in_progress?).to be true
        end
      end

      context "when previous evidence does not exist" do
        before { allow(citizenship_evidence1).to receive(:fetch_last_determined_evidence).and_return(nil) }

        it "returns false" do
          expect(citizenship_evidence1.rop_in_progress?).to be false
        end
      end

      context "when state is not ROP in progress" do
        before do
          citizenship_evidence.current_state = :verified
          citizenship_evidence.save
        end

        it "returns false" do
          expect(citizenship_evidence1.rop_in_progress?).to be false
        end
      end

      context "when due date is in the past" do
        before do
          citizenship_evidence.current_state = :review
          citizenship_evidence.due_on = today - 5.days
          citizenship_evidence.save
        end

        it "returns false" do
          expect(citizenship_evidence1.rop_in_progress?).to be false
        end
      end

      context "when due_on is nil" do
        before do
          citizenship_evidence.current_state = :review
          citizenship_evidence.due_on = nil
          citizenship_evidence.save
        end

        it "returns false" do
          expect(citizenship_evidence1.rop_in_progress?).to be false
        end
      end

      context "when state is nil" do
        before { allow(citizenship_evidence1).to receive(:prev_evidence_state).and_return(nil) }

        it "returns false" do
          expect(citizenship_evidence1.rop_in_progress?).to be false
        end
      end
    end

    describe "#rop_eligible_state" do
      context "when previous evidence is in review state" do
        before do
          citizenship_evidence.current_state = :review
          citizenship_evidence.due_on = today + 5.days
          citizenship_evidence.save
        end

        it "calls copied_review" do
          citizenship_evidence1.rop_eligible_state
          citizenship_evidence1.save
          expect(citizenship_evidence1.current_state).to eq(:review)
          expect(citizenship_evidence1.verification_histories.first.action).to eq('copied_review')
        end
      end

      context "when previous evidence is in outstanding state" do
        before do
          citizenship_evidence.current_state = :outstanding
          citizenship_evidence.due_on = today + 5.days
          citizenship_evidence.save
        end

        it "calls copied_outstanding" do
          citizenship_evidence1.rop_eligible_state
          citizenship_evidence1.save
          expect(citizenship_evidence1.current_state).to eq(:outstanding)
          expect(citizenship_evidence1.verification_histories.first.action).to eq('copied_outstanding')
        end
      end

      context "when previous evidence is in rejected state" do
        before do
          citizenship_evidence.due_on = today + 5.days
          citizenship_evidence.save
          citizenship_evidence1.update_attributes(current_state: :pending)
          allow(citizenship_evidence1).to receive(:can_move_to_rejected?).and_return(true)
        end

        it "calls copied_rejected" do
          citizenship_evidence1.rop_eligible_state
          citizenship_evidence1.save
          expect(citizenship_evidence1.current_state).to eq(:rejected)
          expect(citizenship_evidence1.verification_histories.first.action).to eq('copied_rejected')
        end
      end

      context "when previous evidence is in unexpected state" do
        before do
          citizenship_evidence.current_state = :verified
          citizenship_evidence.save
        end

        it "logs a warning" do
          expect(Rails.logger).to receive(:warn).with("Unexpected state in rop_eligible_state: verified")
          citizenship_evidence1.rop_eligible_state
        end
      end

      context "when previous evidence does not exist" do
        before { allow(citizenship_evidence1).to receive(:fetch_last_determined_evidence).and_return(nil) }

        it "returns without action" do
          present_state = citizenship_evidence1.current_state
          citizenship_evidence1.rop_eligible_state
          expect(citizenship_evidence1.current_state).to eq(present_state)
        end
      end
    end

    describe "#non_rop_eligible_state" do
      context "when person is not found" do
        before { allow(citizenship_evidence1.eligibility.eligible).to receive(:find_person).and_return(nil) }

        it "moves to negative_response_received" do
          citizenship_evidence1.non_rop_eligible_state
          expect(citizenship_evidence1.current_state).to eq(:negative_response_received)
        end
      end

      context "when person has no active enrollment" do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?)
            .with(:set_due_date_upon_response_from_hub).and_return(false)
          allow(ivl_eligibility1.eligible).to receive(:find_person).and_return(person)
        end

        it "moves to negative_response_received" do
          citizenship_evidence1.non_rop_eligible_state
          expect(citizenship_evidence1.current_state).to eq(:negative_response_received)
        end
      end
    end
  end
end
