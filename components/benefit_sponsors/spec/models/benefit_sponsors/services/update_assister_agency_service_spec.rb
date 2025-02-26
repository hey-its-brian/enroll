# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::BenefitSponsors::Services::UpdateAssisterAgencyService, type: :model, :dbclean => :after_each do
  let(:params) do
    {
      :legal_name => assister_agency_profile.legal_name
    }
  end
  let(:service_class) { BenefitSponsors::Services::UpdateAssisterAgencyService }
  let!(:assister_agency_account) {FactoryBot.build(:benefit_sponsors_accounts_assister_agency_account, assister_agency_profile: assister_agency_profile)}


  let!(:rating_area)                  { FactoryBot.create_default :benefit_markets_locations_rating_area }
  let!(:service_area)                 { FactoryBot.create_default :benefit_markets_locations_service_area }
  let(:site)                          { create(:benefit_sponsors_site, :with_benefit_market, :as_hbx_profile, :cca) }
  let(:organization)                  { FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_aca_shop_cca_employer_profile, site: site) }
  let(:employer_profile)              { organization.employer_profile }
  let(:active_benefit_sponsorship)    do
    sponsor = employer_profile.add_benefit_sponsorship
    sponsor.assister_agency_accounts << assister_agency_account
    sponsor.organization.save
    sponsor
  end

  let!(:assister_organization)    { FactoryBot.build(:benefit_sponsors_organizations_general_organization, site: site)}
  let!(:assister_agency_profile) { FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile, organization: assister_organization, legal_name: 'Legal Name1') }
  let!(:person1) { FactoryBot.create(:person) }
  let!(:assister_role1) { FactoryBot.create(:assister_role, aasm_state: 'active', benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id, person: person1) }




  describe "#new" do
    let(:service_obj) { service_class.new(params)}
    it "should instantiate" do
      expect(service_obj.legal_name).to eq assister_agency_profile.legal_name
      expect(service_obj.assister_agency).to eq assister_agency_profile
    end
  end

  describe "#update_assister_profile_id" do

    before :each do
      old_assister_agency_profile.update_attributes(primary_assister_role: person1.assister_role)
      person.assister_role.update_attributes!(benefit_sponsors_assister_agency_profile_id: old_assister_agency_profile.id)
    end

    let(:formed_params) do
      {
        hbx_id: person.hbx_id
      }
    end
    let(:person) { FactoryBot.create(:person, :with_assister_role)}
    let!(:old_assister_agency_profile) { BenefitSponsors::Organizations::AssisterAgencyProfile.new }
    let!(:assister_agency_staff_role) { FactoryBot.create(:assister_agency_staff_role, benefit_sponsors_assister_agency_profile_id: old_assister_agency_profile.id, person: person) }

    it "should update profile_id" do
      service_obj = service_class.new(params)
      service_obj.update_assister_profile_id(formed_params)
      expect(person.assister_agency_staff_roles.first.benefit_sponsors_assister_agency_profile_id).to eq person.assister_role.benefit_sponsors_assister_agency_profile_id
    end
  end

  describe "#update_assister_agency_attributes" do
    let(:service_obj) { service_class.new(params)}

    it "should update corporate_aoid" do
      service_obj.update_assister_agency_attributes({corporate_aoid: "12234234"})
      assister_agency_profile.reload
      expect(assister_agency_profile.corporate_aoid).to eq "12234234"
    end
  end

  describe "#update_organization_attributes" do
    let(:service_obj) { service_class.new(params)}

    it "should update organization fein" do
      service_obj.update_organization_attributes({fein: "097979787"})
      assister_agency_profile.organization.reload
      expect(assister_agency_profile.organization.fein).to eq "097979787"
    end
  end

  describe "#update_assister_assignment_date" do
    let(:service_obj) { service_class.new(params)}
    let!(:start_date) { DateTime.new(2018, 8, 29, 0, 0, 0).change(day: 1)  }
    let!(:formed_params) { {hbx_ids: [organization.hbx_id], start_date: start_date}}

    it "should update assister agnecy account start date" do
      organization.benefit_sponsorships << active_benefit_sponsorship
      organization.save
      service_obj.update_assister_assignment_date(formed_params)
      expect(assister_agency_account.reload.start_on).to eq start_date
    end
  end
end