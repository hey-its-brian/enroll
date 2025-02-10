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
end
