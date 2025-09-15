# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::AgeOffRelaxedEligibility, dbclean: :after_each do
  context 'aca_individual_dependent_age_off' do
    context 'with:
      - for renewal effective year
      - dependent member is born on 1st of the year
      - dependent member turns 26 on the effective date
      - dependent member has an active enrollment in the current year
    ' do
      let(:renewal_effective_on) { Date.new(TimeKeeper.date_of_record.year.next, 1, 1) }
      let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
      let(:configured_age_off) { EnrollRegistry[:aca_individual_dependent_age_off].setting(:cut_off_age).item }
      let(:relationship_kind) { EnrollRegistry[:aca_individual_dependent_age_off].setting(:relationship_kinds).item.sample }
      let(:person2) do
        per = FactoryBot.create(:person, :with_consumer_role, dob: Date.new(TimeKeeper.date_of_record.year.next - configured_age_off, 1, 1))
        person.ensure_relationship_with(per, relationship_kind)
        per
      end
      let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let(:primary) { family.primary_applicant }
      let(:dependent) { FactoryBot.create(:family_member, family: family, person: person2) }
      let(:enrollment) do
        enr = FactoryBot.create(:hbx_enrollment, :individual_unassisted, family: family, household: family.active_household, effective_on: TimeKeeper.date_of_record.beginning_of_year)
        FactoryBot.create(:hbx_enrollment_member, applicant_id: primary.id, hbx_enrollment: enr)
        FactoryBot.create(:hbx_enrollment_member, applicant_id: dependent.id, hbx_enrollment: enr, is_subscriber: false)
        enr
      end

      before :each do
        enrollment
      end

      it 'returns success with false' do
        result = subject.call(
          {
            effective_on: renewal_effective_on,
            family_member: dependent,
            market_key: :aca_individual_dependent_age_off,
            relationship_kind: relationship_kind
          }
        )
        expect(result.success).not_to be_truthy
      end
    end
  end
end
