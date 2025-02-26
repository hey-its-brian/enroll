# frozen_string_literal: true

require "rails_helper"

describe Operations::EnsureAssisterStaffRoleForPrimaryAssister, "given an invalid scenario" do
  subject do
    described_class.new(:some_garbage)
  end

  it "raises an error" do
    expect { subject }.to raise_error(ArgumentError)
  end
end

describe Operations::EnsureAssisterStaffRoleForPrimaryAssister, "when:
  - it is for the scenario of :consumer_role_linked
  - the person has no assister role", dbclean: :after_each do

  let(:operation) do
    described_class.new(:consumer_role_linked)
  end

  let(:consumer_role) do
    FactoryBot.create(:consumer_role)
  end

  let(:person) do
    pers = consumer_role.person
    pers.user = user
    pers.save!
    pers
  end

  let(:user) do
    FactoryBot.create(:user)
  end

  before :each do
    operation.call(nil)
  end

  it "does not add a staff role" do
    expect(person.assister_agency_staff_roles).to eq []
  end
end

describe Operations::EnsureAssisterStaffRoleForPrimaryAssister, "when:
  - it is for the scenario of :consumer_role_linked
  - the person has an unapproved assister role", dbclean: :after_each do

  let(:operation) do
    described_class.new(:consumer_role_linked)
  end

  let(:consumer_role) do
    FactoryBot.create(:consumer_role)
  end

  let(:person) do
    pers = consumer_role.person
    pers.user = user
    pers.save!
    pers
  end

  let(:assister_agency_profile) do
    FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile)
  end

  let(:user) do
    FactoryBot.create(:user)
  end

  let(:existing_assister_staff_role) do
    person.assister_agency_staff_roles.first
  end

  let(:assister_role) do
    role = AssisterRole.new(
      :assister_agency_profile => assister_agency_profile,
      :aasm_state => "applicant",
      :assister_org_id => "123456789",
      :provider_kind => "assister"
    )
    person.assister_role = role
    person.save!
    person.assister_role
  end

  before :each do
    operation.call(assister_role)
  end

  it "does not add a staff role" do
    expect(person.assister_agency_staff_roles).to eq []
  end
end

describe Operations::EnsureAssisterStaffRoleForPrimaryAssister, "when:
  - it is for the scenario of :consumer_role_linked
  - the person has an approved assister role
  - the person already has a assister staff role for the same brokerage", dbclean: :after_each do
  let(:operation) do
    described_class.new(:consumer_role_linked)
  end

  let(:consumer_role) do
    FactoryBot.create(:consumer_role)
  end

  let(:person) do
    pers = consumer_role.person
    pers.user = user
    pers.assister_agency_staff_roles << AssisterAgencyStaffRole.new(
      aasm_state: "assister_agency_pending",
      assister_agency_profile: assister_agency_profile
    )
    pers.save!
    pers
  end

  let(:assister_agency_profile) do
    FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile)
  end

  let(:user) do
    FactoryBot.create(:user)
  end

  let(:existing_assister_staff_role) do
    person.assister_agency_staff_roles.first
  end

  let(:assister_role) do
    role = AssisterRole.new(
      :assister_agency_profile => assister_agency_profile,
      :aasm_state => "active",
      :assister_org_id => "123456789",
      :provider_kind => "assister"
    )
    person.assister_role = role
    person.save!
    person.assister_role
  end

  before :each do
    operation.call(assister_role)
  end

  it "doesn't add another assister staff role" do
    expect(person.assister_agency_staff_roles.count).to eq 1
  end

  it "activates the assister staff role" do
    expect(existing_assister_staff_role.aasm_state).to eq "active"
  end
end

describe Operations::EnsureAssisterStaffRoleForPrimaryAssister, "when:
  - it is for the scenario of :consumer_role_linked
  - the person has an approved assister role
  - the person doesn't have a assister staff role for the same brokerage", dbclean: :after_each do
  let(:operation) do
    described_class.new(:consumer_role_linked)
  end

  let(:consumer_role) do
    FactoryBot.create(:consumer_role)
  end

  let(:person) do
    pers = consumer_role.person
    pers.user = user
    pers.save!
    pers
  end

  let(:assister_agency_profile) do
    FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile)
  end

  let(:user) do
    FactoryBot.create(:user)
  end

  let(:assister_role) do
    role = AssisterRole.new(
      :assister_agency_profile => assister_agency_profile,
      :aasm_state => "active",
      :assister_org_id => "123456789",
      :provider_kind => "assister"
    )
    person.assister_role = role
    person.save!
    person.assister_role
  end

  before :each do
    operation.call(assister_role)
  end

  it "creates a new assister staff role for the same brokerage" do
    expect(person.assister_agency_staff_roles.first.assister_agency_profile.id).to eq assister_agency_profile.id
  end

  it "sets the new role to active" do
    new_assister_staff_role = person.assister_agency_staff_roles.first
    expect(new_assister_staff_role.aasm_state).to eq "active"
  end
end
