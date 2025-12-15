# frozen_string_literal: true

require 'rails_helper'

RSpec.describe HbxEnrollment, type: :model do
  describe 'duplicate hbx_id' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:hbx_enrollment1) do
      FactoryBot.create(
        :hbx_enrollment,
        household: family.active_household,
        coverage_kind: 'health',
        effective_on: TimeKeeper.date_of_record.beginning_of_month,
        family: family
      )
    end

    let(:hbx_enrollment2) do
      FactoryBot.create(
        :hbx_enrollment,
        household: family.active_household,
        coverage_kind: 'health',
        effective_on: TimeKeeper.date_of_record.beginning_of_month,
        family: family,
        hbx_id: enrollment_hbx_id
      )
    end

    before do
      hbx_enrollment1
      HbxEnrollment.remove_indexes
      HbxEnrollment.create_indexes
    end

    context 'when hbx_id is not unique' do
      let(:enrollment_hbx_id) { hbx_enrollment1.hbx_id }

      it 'raises error' do
        expect { hbx_enrollment2 }.to raise_error(
          Mongo::Error::OperationFailure
        ).with_message(/E11000 duplicate key error/)
      end
    end

    context 'when hbx_id is unique' do
      let(:enrollment_hbx_id) { '1234567890' }

      it 'creates hbx enrollment' do
        expect(hbx_enrollment2).to be_a(HbxEnrollment)
      end
    end
  end

  describe 'transitions without publishing events or invoking noisy callbacks' do
    let(:rating_area) { FactoryBot.create_default(:benefit_markets_locations_rating_area) }
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:consumer_role) { person.consumer_role }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:hbx_enrollment) do
      FactoryBot.create(
        :hbx_enrollment,
        :individual_unassisted,
        :with_health_product,
        family: family,
        household: family.active_household,
        coverage_kind: 'health',
        effective_on: TimeKeeper.date_of_record.beginning_of_month,
        consumer_role: consumer_role,
        rating_area_id: rating_area.id,
        aasm_state: aasm_state
      )
    end

    context "#select_coverage" do
      let(:aasm_state) { 'shopping' }

      it "moves enrollment to coverage_selected state with noisy callbacks" do
        expect(hbx_enrollment).to receive(:generate_enrollment_saved_event)
        expect(hbx_enrollment.aasm_state).to eq 'shopping'
        hbx_enrollment.select_coverage
        expect(hbx_enrollment.aasm_state).to eq 'coverage_selected'
        expect(hbx_enrollment.workflow_state_transitions.last.to_state).to eq 'coverage_selected'
        expect(hbx_enrollment.workflow_state_transitions.last.from_state).to eq 'shopping'
      end
    end

    context "#move_to_enrolled" do
      let(:aasm_state) { 'unverified' }

      it "moves enrollment to coverage_selected state without noisy callbacks" do
        expect(hbx_enrollment).not_to receive(:generate_enrollment_saved_event)
        expect(hbx_enrollment.aasm_state).to eq 'unverified'
        hbx_enrollment.move_to_enrolled
        expect(hbx_enrollment.aasm_state).to eq 'coverage_selected'
        expect(hbx_enrollment.workflow_state_transitions.last.to_state).to eq 'coverage_selected'
        expect(hbx_enrollment.workflow_state_transitions.last.from_state).to eq 'unverified'
      end
    end

    context "#move_to_pending" do
      let(:aasm_state) { 'coverage_selected' }
      it "moves enrollment to unverified state without noisy callbacks" do
        expect(hbx_enrollment).not_to receive(:generate_enrollment_saved_event)
        expect(hbx_enrollment.aasm_state).to eq 'coverage_selected'
        hbx_enrollment.move_to_pending
        expect(hbx_enrollment.aasm_state).to eq 'unverified'
        expect(hbx_enrollment.workflow_state_transitions.last.to_state).to eq 'unverified'
        expect(hbx_enrollment.workflow_state_transitions.last.from_state).to eq 'coverage_selected'
      end
    end
  end
end
