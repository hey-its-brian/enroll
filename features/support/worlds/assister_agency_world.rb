# frozen_string_literal: true

# factory helper to create AssisterAgency and associations.
module AssisterAgencyWorld
  def create_prospect_employer(assister_agency_name)
    assister_agency_profile = assister_agency_profile(assister_agency_name)
    organization_params = {
      "legal_name" => "emp1",
      "dba" => "101010",
      "entity_kind" => "c_corporation",
      "office_locations_attributes" => {
        "0" => {
          "address_attributes" => {
            "kind" => "primary",
            "address_1" => "1818 exp st",
            "address_2" => "",
            "city" => EnrollRegistry[:enroll_app].setting(:contact_center_city).item,
            "state" => EnrollRegistry[:enroll_app].setting(:state_abbreviation).item,
            "zip" => EnrollRegistry[:enroll_app].setting(:contact_center_zip_code).item
          },
          "phone_attributes" => {
            "kind" => "work", "area_code" => "202", "number" => "555-2121", "extension" => ""
          }
        }
      }
    }
    SponsoredBenefits::Organizations::AssisterAgencyProfile.init_prospect_organization(
      assister_agency_profile,
      organization_params.merge(owner_profile_id: assister_agency_profile.id)
    )
  end

  def assign_assister_agency_account(assister_name, assister_agency_name)
    assister_agency_profile = assister_agency_profile(assister_agency_name)
    sponsorship = employer_profile.benefit_sponsorships.first
    sponsorship.assister_agency_accounts << build(:benefit_sponsors_accounts_assister_agency_account, assister_agency_profile: assister_agency_profile, writing_agent_id: @assisters[assister_name].id)
    sponsorship.organization.save!
  end

  def assister_agency_organization(legal_name = nil, *traits)
    attributes = traits.extract_options!
    traits.push(:with_assister_agency_profile)
    @assister_agency_profiles ||= {}

    if legal_name.blank?
      if @assister_agency_profiles.empty?
        @assister_agency_profiles[:default] ||= FactoryBot.create(:benefit_sponsors_organizations_general_organization,
                                                                  *traits,
                                                                  attributes.merge(site: site))
      else
        @assister_agency_profiles.values.first
      end
    else
      @assister_agency_profiles[legal_name] ||= FactoryBot.create(:benefit_sponsors_organizations_general_organization,
                                                                  *traits,
                                                                  attributes.merge(site: site))
    end
  end

  def all_assister_agencies
    Person.all.select { |p| p.assister_role.present? }.map { |person| person.assister_role.assister_agency_profile }
  end

  def assister_agency_profile(legal_name = nil)
    assister_agency_organization(legal_name).assister_agency_profile if assister_agency_organization(legal_name).present?
  end

  def assign_assister_to_assister_agency(assister_name, legal_name)
    @assisters ||= {}
    return @assisters[assister_name] if @assisters[assister_name]

    assister_agency_profile = assister_agency_profile(legal_name)
    person = FactoryBot.create(:person, :with_work_email, first_name: assister_name.split(/\s/)[0], last_name: assister_name.split(/\s/)[1])
    @assisters[assister_name] = create(:assister_role, aasm_state: 'active', benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id, person: person)
    person.assister_agency_staff_roles << build(:assister_agency_staff_role, assister_agency_profile_id: assister_agency_profile.id)
    @assister_agency_staff = create(:user, person: person, email: people[assister_name][:email], password: people[assister_name][:password], password_confirmation: people[assister_name][:password])
    @assister_agency_staff.update_attributes(last_portal_visited: "/benefit_sponsors/profiles/assister_agencies/assister_agency_profiles/#{assister_agency_profile.id}")
  end

  def plan_design_organization(employer_name, assister_agency_name = nil)
    sponsor = employer_profile(employer_name)
    @plan_design_organization ||= FactoryBot.create(:sponsored_benefits_plan_design_organization,
                                                    owner_profile_id: assister_agency_profile(assister_agency_name).id,
                                                    sponsor_profile_id: sponsor.id,
                                                    legal_name: sponsor.legal_name,
                                                    dba: sponsor.dba,
                                                    fein: sponsor.fein,
                                                    has_active_assister_relationship: true)
  end

  def create_person_record(name)
    person = people[name]
    person_rec = FactoryBot.create(:person, first_name: person[:first_name], last_name: person[:last_name], dob: Date.strptime(person[:dob], "%m/%d/%Y"))
    FactoryBot.create(:user, person: person_rec, email: person[:email])
  end

  def assister_agency_profile_with_organization(*traits)
    attributes = traits.extract_options!
    @assister_agency_profile_with_organization ||= FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile, *traits, attributes)
  end
end

World(AssisterAgencyWorld)

Given(/^an individual market assister exists$/) do
  @assister_agency_profile = assister_agency_profile_with_organization market_kind: :individual
  assister :with_family, :assister_with_person, organization: @assister_agency_profile.organization
end

And(/^a consumer role family exists with assister$/) do
  @person = FactoryBot.create(:person, :with_family, :with_consumer_role)
  @person.consumer_role.move_identity_documents_to_verified
  @person.primary_family.assister_agency_accounts.create!(
    start_on: TimeKeeper.date_of_record,
    benefit_sponsors_assister_agency_profile_id: @assister_agency_profile.id,
    writing_agent_id: @assister_agency_profile.primary_assister_role.id,
    is_active: true
  )
end

And(/^assister lands on assister agency home page$/) do
  visit benefit_sponsors.profiles_assister_agencies_assister_agency_profile_path(id: @assister_agency_profile)
end

And(/^assister clicks on the name of the person in family index$/) do
  person_name = @person&.first_name || 'John'
  find('a', :text => person_name, :wait => 10).click
end

Given(/^there is a Assister Agency exists for (.*?)$/) do |assister_agency_name|
  assister_agency_organization assister_agency_name, legal_name: assister_agency_name, dba: assister_agency_name

  assister_agency_profile(assister_agency_name).update_attributes!(aasm_state: 'is_approved')
end


# Following step will move assister role to the given state
# ex: the assister Max Planck application is in denied
#     the assister Max Planck application is in applicant
#     the assister Max Planck application is in decertified
And(/^the assister (.*?) application is in (.*?) state$/) do |assister_name, assister_role_state|
  @assisters[assister_name].update_attributes(aasm_state: assister_role_state)
  # makes the current assister as the primary assister of the organization
  assister_agency_profile.update_attributes!(primary_assister_role_id: @assisters[assister_name].id)
  # Don't need a staff role for this scenario
  @assisters[assister_name].person.assister_agency_staff_roles[0].destroy
end

And(/^the assister (.*?) is primary assister for (.*?)$/) do |assister_name, assister_agency_name|
  assign_assister_to_assister_agency(assister_name, assister_agency_name)
end

And(/^employer (.*?) is listed under the account for assister (.*?)$/) do |employer_name, assister_agency_name|
  employer = BenefitSponsors::Organizations::Organization.all.detect { |org| org.legal_name == employer_name }
  sponsorship = employer.employer_profile.benefit_sponsorships.last
  assister_agency = BenefitSponsors::Organizations::Organization.all.detect { |org| org.legal_name == assister_agency_name }
  assister_agency_prof = assister_agency.assister_agency_profile
  assister_agency_under_sponsorships = sponsorship.assister_agency_accounts.detect { |assister_agency_account| assister_agency_account.assister_agency_profile == assister_agency_prof }
  raise("No assister agency under sponsorship") if assister_agency_under_sponsorships.blank?
  dt_query = nil
  query = BenefitSponsors::Queries::AssisterFamiliesQuery.new(dt_query, assister_agency_prof.id, assister_agency_prof.market_kind)
  census_employee_names = employer.employer_profile.census_employees.map(&:full_name)
  query_family_primary_person_names = query.filtered_scope.map { |query_family| query_family&.primary_person&.full_name }
  census_employee_names.each { |ce_name| expect(query_family_primary_person_names).to include(ce_name) }
end

And(/^employer (.*?) hired assister (.*?) from (.*?)$/) do |employer_name, assister_name, assister_agency_name|
  plan_design_organization(employer_name, assister_agency_name)
  assign_assister_agency_account(assister_name, assister_agency_name)
end

And(/^Hbx Admin is on Assister Index of the Admin Dashboard$/) do
  visit exchanges_hbx_profiles_path
  find('.interaction-click-control-assisters').click
end

Then(/^Hbx Admin is on Assister Index and clicks Assister Applicants$/) do
  find('.interaction-click-control-assister-applications').click
end

Then(/^Assister Hbx Admin clicks on (.*?) tab$/) do |tab_name|
  find("label", text: tab_name.titleize).click
end

Then(/^Hbx Admin is on Assister Index and clicks Assister Agencies$/) do
  find('.interaction-click-control-assister-agencies').click
end

Then(/^Hbx Admin clicks on the current assister applicant show button$/) do
  wait_for_ajax
  find_all('.interaction-click-control-assister-show').first.click
  expect(page).to have_content(/HBX/i)
end
