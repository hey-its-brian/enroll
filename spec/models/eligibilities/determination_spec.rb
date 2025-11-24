# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::Determination, type: :model, dbclean: :after_each do
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

  describe '#refresh_enrollment_eligibilities' do
    let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, benefit_market_kind: :aca_individual) }
    let!(:enrollment) do
      enr = FactoryBot.create(:hbx_enrollment,
                              household: family.active_household,
                              family: family,
                              kind: "individual",
                              aasm_state: 'coverage_selected',
                              effective_on: TimeKeeper.date_of_record.beginning_of_month,
                              product: product)

      FactoryBot.create(:hbx_enrollment_member,
                        hbx_enrollment: enr,
                        applicant_id: family.primary_applicant.id,
                        is_subscriber: true,
                        eligibility_date: TimeKeeper.date_of_record.beginning_of_month,
                        coverage_start_on: TimeKeeper.date_of_record.beginning_of_month)

      enr.reload
      enr
    end

    context 'when determination is created with outstanding subject' do
      before do
        enrollment.update_attributes!(is_any_enrollment_member_outstanding: false)

        det = family.build_eligibility_determination(
          effective_date: TimeKeeper.date_of_record.beginning_of_month
        )

        det.subjects.build(
          person_id: primary_person.id.to_s,
          gid: family.primary_applicant.to_global_id,
          outstanding_verification_status: 'outstanding'
        )

        det.save!
        family.save!
      end

      it 'updates enrollment is_any_enrollment_member_outstanding flag to true' do
        enrollment.reload
        expect(enrollment.is_any_enrollment_member_outstanding).to be_truthy
      end
    end

    context 'when determination is updated from outstanding to verified' do
      before do
        det = family.build_eligibility_determination(
          effective_date: TimeKeeper.date_of_record.beginning_of_month
        )

        det.subjects.build(
          person_id: primary_person.id.to_s,
          gid: family.primary_applicant.to_global_id,
          outstanding_verification_status: 'outstanding'
        )

        det.save!
        family.save!

        enrollment.reload
        expect(enrollment.is_any_enrollment_member_outstanding).to be_truthy
      end

      it 'updates enrollment flag to false when subject becomes verified' do
        family.eligibility_determination.subjects.first.update_attributes(outstanding_verification_status: 'verified')
        family.eligibility_determination.save!

        enrollment.reload
        expect(enrollment.is_any_enrollment_member_outstanding).to be_falsey
      end
    end

    context 'when determination has mixed statuses' do
      let(:spouse_person) { FactoryBot.create(:person, :with_consumer_role) }
      let!(:spouse_family_member) do
        family.add_family_member(spouse_person, is_primary_applicant: false)
        family.relate_new_member(spouse_person, 'spouse')
        family.save!
        family.family_members.detect { |fm| fm.person_id == spouse_person.id }
      end

      let!(:enrollment_with_spouse) do
        enr = FactoryBot.create(:hbx_enrollment,
                                household: family.active_household,
                                family: family,
                                kind: "individual",
                                aasm_state: 'coverage_selected',
                                effective_on: TimeKeeper.date_of_record.beginning_of_month,
                                product: product)

        FactoryBot.create(:hbx_enrollment_member,
                          hbx_enrollment: enr,
                          applicant_id: family.primary_applicant.id,
                          is_subscriber: true,
                          eligibility_date: TimeKeeper.date_of_record.beginning_of_month,
                          coverage_start_on: TimeKeeper.date_of_record.beginning_of_month)

        FactoryBot.create(:hbx_enrollment_member,
                          hbx_enrollment: enr,
                          applicant_id: spouse_family_member.id,
                          is_subscriber: false,
                          eligibility_date: TimeKeeper.date_of_record.beginning_of_month,
                          coverage_start_on: TimeKeeper.date_of_record.beginning_of_month)

        enr.reload
        enr
      end

      before do
        enrollment_with_spouse.update_attributes!(is_any_enrollment_member_outstanding: false)

        det = family.build_eligibility_determination(
          effective_date: TimeKeeper.date_of_record.beginning_of_month
        )

        det.subjects.build(
          person_id: primary_person.id.to_s,
          gid: family.primary_applicant.to_global_id,
          outstanding_verification_status: 'verified'
        )

        det.subjects.build(
          person_id: spouse_person.id.to_s,
          gid: spouse_family_member.to_global_id,
          outstanding_verification_status: 'outstanding'
        )

        det.save!
        family.save!
      end

      it 'updates enrollment flag to true when any enrolled member has outstanding' do
        enrollment_with_spouse.reload
        expect(enrollment_with_spouse.is_any_enrollment_member_outstanding).to be_truthy
      end
    end

    context 'when enrollment is terminated' do
      before do
        enrollment.terminate_coverage!

        det = family.build_eligibility_determination(
          effective_date: TimeKeeper.date_of_record.beginning_of_month
        )

        det.subjects.build(
          person_id: primary_person.id.to_s,
          gid: family.primary_applicant.to_global_id,
          outstanding_verification_status: 'outstanding'
        )

        det.save!
        family.save!
      end

      it 'does not update terminated enrollments' do
        enrollment.reload
        expect(enrollment.aasm_state).to eq 'coverage_terminated'
      end
    end

    context 'when family has multiple enrollments' do
      let!(:enrollment2) do
        enr = FactoryBot.create(:hbx_enrollment,
                                household: family.active_household,
                                family: family,
                                kind: "individual",
                                aasm_state: 'coverage_selected',
                                effective_on: TimeKeeper.date_of_record.beginning_of_month,
                                product: product)

        FactoryBot.create(:hbx_enrollment_member,
                          hbx_enrollment: enr,
                          applicant_id: family.primary_applicant.id,
                          is_subscriber: true,
                          eligibility_date: TimeKeeper.date_of_record.beginning_of_month,
                          coverage_start_on: TimeKeeper.date_of_record.beginning_of_month)

        enr.reload
        enr
      end

      before do
        enrollment.update_attributes!(is_any_enrollment_member_outstanding: false)
        enrollment2.update_attributes!(is_any_enrollment_member_outstanding: false)

        det = family.build_eligibility_determination(
          effective_date: TimeKeeper.date_of_record.beginning_of_month
        )

        det.subjects.build(
          person_id: primary_person.id.to_s,
          gid: family.primary_applicant.to_global_id,
          outstanding_verification_status: 'outstanding'
        )

        det.save!
        family.save!
      end

      it 'updates all active individual market enrollments' do
        enrollment.reload
        enrollment2.reload

        expect(enrollment.is_any_enrollment_member_outstanding).to be_truthy
        expect(enrollment2.is_any_enrollment_member_outstanding).to be_truthy
      end
    end

    context 'when determinable is not a Family' do
      let(:non_family_determinable) { double('NonFamily') }
      let(:determination_non_family) do
        FactoryBot.build(:eligibilities_determination)
      end

      it 'does not raise error' do
        allow(determination_non_family).to receive(:determinable).and_return(non_family_determinable)
        expect { determination_non_family.refresh_enrollment_eligibilities }.not_to raise_error
      end
    end
  end
end