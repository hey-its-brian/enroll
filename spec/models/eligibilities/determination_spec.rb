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

  describe '#member_medicaid_eligible?' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:family_member) { family.primary_applicant }

    let(:year) { TimeKeeper.date_of_record.year }
    let!(:determination) do
      det = FactoryBot.build(:eligibilities_determination, effective_date: TimeKeeper.date_of_record.beginning_of_month)

      # Create subject with medicaid grant
      subject = FactoryBot.build(
        :eligibilities_subject,
        person_id: person.id.to_s,
        gid: family_member.to_global_id
      )

      eligibility_state = FactoryBot.build(
        :eligibilities_eligibility_state,
        eligibility_item_key: 'aptc_csr_credit'
      )

      # Create magi medicaid grant
      magi_grant = FactoryBot.build(
        :eligibilities_grant,
        key: 'MagiMedicaidGrant',
        member_ids: [family_member.id.to_s]
      )

      subject.eligibility_states << eligibility_state
      subject.eligibility_states.by_type("aptc_csr_credit").first.grants << magi_grant
      det.subjects << subject

      family.eligibility_determination = det
      family.save!
      det
    end

    context "when family member is medicaid eligible" do
      it "returns true" do
        expect(determination.member_medicaid_eligible?(family_member, year)).to be true
      end
    end

    context "when family member is not medicaid eligible" do
      let(:other_person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:other_family_member) { FactoryBot.create(:family_member, family: family, person: other_person) }

      it "returns false" do
        expect(determination.member_medicaid_eligible?(other_family_member, year)).to be false
      end
    end

    context "when subject has no magi medicaid grant" do
      before do
        subject = determination.subjects.first
        eligibility_state = subject.eligibility_states.by_type("aptc_csr_credit").first
        eligibility_state.grants.where(key: 'MagiMedicaidGrant').delete_all
      end

      it "returns false" do
        expect(determination.member_medicaid_eligible?(family_member, year)).to be false
      end
    end
  end

  describe '#shopping_eligible_member_ids' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:family_member) { family.primary_applicant }

    let!(:determination) do
      det = FactoryBot.build(:eligibilities_determination, effective_date: Date.today)
      subject = FactoryBot.build(
        :eligibilities_subject,
        person_id: person.id.to_s,
        gid: family_member.to_global_id
      )

      aptc_state = FactoryBot.build(
        :eligibilities_eligibility_state,
        eligibility_item_key: 'aptc_csr_credit'
      )

      aptc_grant = FactoryBot.build(
        :eligibilities_grant,
        key: 'AdvancePremiumAdjustmentGrant',
        member_ids: [family_member.id.to_s]
      )

      aptc_state.grants << aptc_grant
      subject.eligibility_states << aptc_state

      market_state = FactoryBot.build(
        :eligibilities_eligibility_state,
        eligibility_item_key: 'aca_individual_market_eligibility'
      )

      qhp_grant = FactoryBot.build(
        :eligibilities_grant,
        key: 'QhpGrant',
        member_ids: [family_member.id.to_s]
      )

      market_state.grants << qhp_grant
      subject.eligibility_states << market_state

      det.subjects << subject

      family.eligibility_determination = det
      family.save!
      det
    end

    context "when family member is eligible for shopping" do
      it "returns an array with the family member's id" do
        result = determination.shopping_eligible_member_ids(TimeKeeper.date_of_record.year)
        expect(result).to include(family_member.id.to_s)
      end
    end

    context "when there are no eligible states" do
      before do
        subject = determination.subjects.first
        subject.eligibility_states.delete_all
      end

      it "returns an empty array" do
        expect(determination.shopping_eligible_member_ids(TimeKeeper.date_of_record.year)).to be_empty
      end
    end

    context "when there are eligible states but no eligible grants" do
      before do
        subject = determination.subjects.first
        subject.eligibility_states.each do |state|
          state.grants.delete_all
        end
      end

      it "returns an empty array" do
        expect(determination.shopping_eligible_member_ids(TimeKeeper.date_of_record.year)).to be_empty
      end
    end

    context "when there are non-qualifying eligibility states" do
      before do
        subject = determination.subjects.first
        subject.eligibility_states.each do |state|
          state.update(eligibility_item_key: 'some_other_key')
        end
      end

      it "returns an empty array" do
        expect(determination.shopping_eligible_member_ids(TimeKeeper.date_of_record.year)).to be_empty
      end
    end

    context "when there are non-qualifying grants" do
      before do
        subject = determination.subjects.first
        subject.eligibility_states.each do |state|
          state.grants.each do |grant|
            grant.update(key: 'SomeOtherGrant')
          end
        end
      end

      it "returns an empty array" do
        expect(determination.shopping_eligible_member_ids(TimeKeeper.date_of_record.year)).to be_empty
      end
    end
  end
end
