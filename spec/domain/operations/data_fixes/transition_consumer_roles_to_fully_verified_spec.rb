# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::DataFixes::TransitionConsumerRolesToFullyVerified, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:dependent) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let(:dependent_family_member) { FactoryBot.create(:family_member, family: family, person: dependent) }
  let(:start_date) { TimeKeeper.date_of_record.beginning_of_year }
  let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, benefit_market_kind: 'aca_individual', issuer_profile: issuer_profile, metal_level_kind: :silver) }
  let(:issuer_profile) { FactoryBot.create(:benefit_sponsors_organizations_issuer_profile, :anthm_profile)}
  let(:enrollment) do
    FactoryBot.create(:hbx_enrollment, family: family,
                                       household: family.active_household,
                                       coverage_kind: "health",
                                       kind: "individual",
                                       aasm_state: "coverage_selected",
                                       effective_on: start_date,
                                       product: product,
                                       consumer_role_id: person.consumer_role.id)
  end
  let(:enrollment_members) { FactoryBot.create(:hbx_enrollment_member, hbx_enrollment: enrollment, is_subscriber: true, family_member: family.family_members[0]) }

  before do
    dependent_family_member
    enrollment_members
  end

  context "when consumer roles are in pending state and enrollments are unverified" do
    before do
      enrollment.move_to_pending!
      person.consumer_role.update_attributes(aasm_state: "ssa_pending")
      dependent.consumer_role.update_attributes(aasm_state: "dhs_pending")
    end
    it "should transition consumer roles to fully verified and enrollment to coverage selected" do
      params = { family_id: family.id}
      result = described_class.new.call(params)
      expect(result).to be_success
      person.consumer_role.reload
      dependent.consumer_role.reload
      enrollment.reload
      expect(person.consumer_role.fully_verified?).to be_truthy
      expect(dependent.consumer_role.fully_verified?).to be_truthy
      expect(enrollment.coverage_selected?).to be_truthy
    end
  end

  context "when consumer roles are already fully verified" do
    before do
      enrollment.move_to_pending!
      person.consumer_role.update_attributes(aasm_state: "fully_verified")
      dependent.consumer_role.update_attributes(aasm_state: "fully_verified")
    end
    it "should not change the consumer role states and enrollment state remains unverified" do
      params = { family_id: family.id}
      result = described_class.new.call(params)
      expect(result).to be_success
      person.consumer_role.reload
      dependent.consumer_role.reload
      enrollment.reload
      expect(person.consumer_role.fully_verified?).to be_truthy
      expect(dependent.consumer_role.fully_verified?).to be_truthy
      expect(enrollment.unverified?).to be_truthy
    end
  end


  context "when family id is not present in params" do
    it "should return failure" do
      params = {}
      result = described_class.new.call(params)
      expect(result).to be_failure
      expect(result.failure).to eq("Family id is not present")
    end
  end


  context "when family id is present in params but does not exist in the database" do
    it "should return failure" do
      params = {family_id: 'non_existent_id'}
      result = described_class.new.call(params)
      expect(result).to be_failure
      expect(result.failure).to eq("No family found for the given family id: non_existent_id")
    end
  end
end
