# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::Operations::DataFixes::RemoveInvalidCoverageHouseholdMember, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :male, first_name: 'john', last_name: 'adams', dob: 40.years.ago, ssn: '472743442') }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person)}
  let(:family_member){ FactoryBot.create(:family_member,family: family)}
  let(:active_household) { family.active_household }
  let(:params) { {person_hbx_id: person.hbx_id} }

  it "should remove an inactive family member to household" do
    active_household.immediate_family_coverage_household.coverage_household_members.create(:is_subscriber => true, :family_member_id => "567678789")
    expect(family.active_household.immediate_family_coverage_household.coverage_household_members.size).to eq(2)
    result = described_class.new.call(params)
    expect(result).to be_success
    expect(result.success).to eq("Successfully removed invalid coverage household members")
    active_household.reload
    immediate_family_coverage_household = active_household.immediate_family_coverage_household
    expect(immediate_family_coverage_household.coverage_household_members.size).to eq(1)
    expect(immediate_family_coverage_household.coverage_household_members.first.family_member_id).to eq(family.primary_family_member.id)
  end

  it "should fail" do
    result = described_class.new.call({person_hbx_id: "56353275765217"})
    expect(result).to be_failure
    expect(result.failure).to eq({:message => ["Person not found"]})
  end
end
