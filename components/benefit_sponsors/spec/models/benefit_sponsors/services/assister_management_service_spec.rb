# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::BenefitSponsors::Services::AssisterManagementService, type: :model, :dbclean => :after_each do
  include ::L10nHelper

  subject { BenefitSponsors::Services::AssisterManagementService.new }

  let!(:rating_area)                  { FactoryBot.create_default :benefit_markets_locations_rating_area }
  let!(:service_area)                 { FactoryBot.create_default :benefit_markets_locations_service_area }
  let(:site)                          { create(:benefit_sponsors_site, :with_benefit_market, :as_hbx_profile, EnrollRegistry[:enroll_app].setting(:site_key).item.to_sym) }
  let(:organization)                  { FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_aca_shop_cca_employer_profile, site: site) }
  let(:employer_profile)              { organization.employer_profile }
  let(:active_benefit_sponsorship)    { employer_profile.add_benefit_sponsorship }

  let!(:assister_organization)    { FactoryBot.build(:benefit_sponsors_organizations_general_organization, site: site)}
  let!(:assister_agency_profile1) { FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile, organization: assister_organization, legal_name: 'Legal Name1') }
  let!(:person1) { FactoryBot.create(:person) }
  let!(:assister_role1) { FactoryBot.create(:assister_role, aasm_state: 'active', benefit_sponsors_assister_agency_profile_id: assister_agency_profile1.id, person: person1) }
  let(:assister_management_form_create) do
    BenefitSponsors::Organizations::OrganizationForms::AssisterManagementForm.new(
      employer_profile_id: employer_profile.id,
      assister_agency_profile_id: assister_agency_profile1.id,
      assister_role_id: assister_role1.id
    )
  end

  let(:assister_management_form_terminate) do
    BenefitSponsors::Organizations::OrganizationForms::AssisterManagementForm.new(
      employer_profile_id: employer_profile.id,
      assister_agency_profile_id: assister_agency_profile1.id,
      direct_terminate: 'true',
      termination_date: TimeKeeper.date_of_record.strftime('%m/%d/%Y')
    )
  end
  let(:general_agency_profile) do
    FactoryBot.create(
      :benefit_sponsors_organizations_general_organization,
      :with_site,
      :with_general_agency_profile
    ).profiles.first
  end

  before :each do
    active_benefit_sponsorship.save!
    assister_agency_profile1.update_attributes!(primary_assister_role_id: assister_role1.id)
    assister_agency_profile1.approve!
    organization.reload
  end

  describe 'for assign_agencies' do
    before :each do
      assister_agency_profile1.update_attributes!(default_general_agency_profile_id: general_agency_profile.id)
      subject.assign_agencies(assister_management_form_create)
    end

    it 'should return true once it succesfully assigns assister agency to the employer_profile' do
      expect(subject.assign_agencies(assister_management_form_create)).to be_truthy
    end

    # it 'should send a message to the general_agency' do
    #   general_agency_profile.reload
    #   subject = l10n("employers.assister_agency_notice.subject", assister_legal_name: assister_agency_profile1.organization.legal_name, agency_legal_name: general_agency_profile.legal_name)
    #   body = l10n("employers.assister_agency_notice.body", agency_legal_name: general_agency_profile.legal_name, employer_legal_name: employer_profile.legal_name)
    #   expect(general_agency_profile.inbox.messages.map(&:body)).to include(body)
    #   expect(general_agency_profile.inbox.messages.map(&:subject)).to include(subject)
    # end

    # it 'should send a message to the employer' do
    #   employer_profile.reload
    #   subject = l10n("employers.assister_agency_notice.subject", assister_legal_name: assister_agency_profile1.organization.legal_name, agency_legal_name: general_agency_profile.legal_name)
    #   body = l10n("employers.assister_agency_notice.body", agency_legal_name: general_agency_profile.legal_name, employer_legal_name: employer_profile.legal_name)
    #   expect(employer_profile.inbox.messages.map(&:body)).to include(body)
    #   expect(employer_profile.inbox.messages.map(&:subject)).to include(subject)
    # end

    # it 'should succesfully assigns assister agency to the employer_profile' do
    #   active_benefit_sponsorship.reload
    #   expect(active_benefit_sponsorship.active_assister_agency_account.benefit_sponsors_assister_agency_profile_id).to eq assister_agency_profile1.id
    # end

    # it 'should send a message to the assister' do
    #   person1.reload
    #   expect(person1.inbox.messages.map(&:body)).to include("You have been selected as a assister by #{employer_profile.legal_name}")
    #   expect(person1.inbox.messages.map(&:subject)).to include("You have been select as the assister")
    # end
  end

  describe 'for terminate_agencies' do
    before :each do
      subject.assign_agencies(assister_management_form_create)
    end

    it 'should return true once it succesfully assigns assister agency to the employer_profile' do
      expect(subject.terminate_agencies(assister_management_form_terminate)).to be_truthy
    end

    # it 'should succesfully assigns assister agency to the employer_profile' do
    #   active_benefit_sponsorship.reload
    #   expect(active_benefit_sponsorship.assister_agency_accounts).not_to eq []
    #   subject.terminate_agencies(assister_management_form_terminate)
    #   active_benefit_sponsorship.reload
    #   expect(active_benefit_sponsorship.assister_agency_accounts).to eq []
    # end
  end
end