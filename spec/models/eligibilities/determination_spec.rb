# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::Determination, type: :model do
  let(:primary_person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: primary_person) }
  let(:dependent_person) do
    person = FactoryBot.create(:person, :with_consumer_role)
    primary_person.ensure_relationship_with(person, 'child')
    person.save!
    person
  end
  let(:dependent_family_member) { FactoryBot.create(:family_member, family: family, person: dependent_person) }
  let(:determination) do
    determination = FactoryBot.build(
      :eligibilities_determination,
      subjects: [
        FactoryBot.build(
          :eligibilities_subject,
          gid: dependent_family_member.to_global_id,
          eligibility_states: [
            FactoryBot.build(
              :eligibilities_eligibility_state,
              evidence_states: [
                FactoryBot.build(
                  :eligibilities_evidence_state,
                  status: :outstanding
                )
              ]
            )
          ]
        )
      ]
    )
    family.eligibility_determination = determination
    family.save!
    determination
  end

  describe 'subjects_action_needed?' do
    context 'when there are active subjects with action needed' do
      it 'returns true' do
        expect(family.family_members.all?(&:is_active?)).to be true
        expect(determination.subjects_action_needed?).to be true
      end
    end

    context 'when there are no active subjects with action needed' do
      before { dependent_family_member.update(is_active: false) }

      it 'returns false' do
        expect(determination.subjects_action_needed?).to be false
      end
    end
  end
end
