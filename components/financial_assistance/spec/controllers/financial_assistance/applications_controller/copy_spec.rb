# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::ApplicationsController, dbclean: :after_each, type: :controller do
  include Dry::Monads[:do, :result]

  before :all do
    DatabaseCleaner.clean
  end

  routes { FinancialAssistance::Engine.routes }
  let(:event) { Success(double) }
  let(:obj)  { FinancialAssistance::Operations::Applications::MedicaidGateway::PublishApplication.new }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, hbx_id: 1234)}
  let(:hbx_staff_role) { double("hbx_staff_role")}
  let!(:user) { FactoryBot.create(:user, :person => person) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:family_id) { family.id}
  let(:family_member_id) { family.primary_applicant.id }
  let!(:application) { FactoryBot.create(:application, hbx_id: 1234, assistance_year: Date.today.year, created_at: Date.today - 1.day, family_id: family_id, aasm_state: "draft", effective_date: TimeKeeper.date_of_record) }
  let!(:applicant) do
    applicant = FactoryBot.create(:applicant,
                                  person_hbx_id: 1234,
                                  family_member_id: family_member_id,
                                  first_name: person.first_name,
                                  last_name: person.last_name,
                                  dob: person.dob,
                                  gender: person.gender,
                                  ssn: person.ssn,
                                  application: application,
                                  ethnicity: [],
                                  is_self_attested_blind: false,
                                  is_primary_applicant: true,
                                  is_applying_coverage: true,
                                  is_required_to_file_taxes: true,
                                  is_pregnant: false,
                                  has_job_income: false,
                                  has_self_employment_income: false,
                                  has_unemployment_income: false,
                                  has_other_income: false,
                                  has_deductions: false,
                                  has_daily_living_help: false,
                                  need_help_paying_bills: false,
                                  has_enrolled_health_coverage: false,
                                  has_eligible_health_coverage: false,
                                  has_eligible_medicaid_cubcare: false,
                                  is_claimed_as_tax_dependent: false,
                                  is_incarcerated: false,
                                  is_post_partum_period: false,
                                  citizen_status: 'us_citizen')
    applicant
  end
  let!(:application2) { FactoryBot.create(:application, hbx_id: 3456, assistance_year: Date.today.year + 1, created_at: Date.today + 1.day, family_id: family_id, aasm_state: "draft", effective_date: TimeKeeper.date_of_record) }
  let!(:applicant2) { FactoryBot.create(:applicant, application: application2,  family_member_id: family_member_id) }
  let(:application_valid_params) { {"medicaid_terms" => "yes", "report_change_terms" => "yes", "medicaid_insurance_collection_terms" => "yes", "parent_living_out_of_home_terms" => "true", "attestation_terms" => "yes", "submission_terms" => "yes"} }
  let!(:hbx_profile) {FactoryBot.create(:hbx_profile,:open_enrollment_coverage_period)}
  let(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
  let(:admin_user) { FactoryBot.create(:user, :with_hbx_staff_role, :person => admin_person, oim_id: '1234567899', email: 'test@test.com') }

  #set of objects that doesnt belong to the first family/user to validate the records returned only belong to the user logged in
  let(:person10) { FactoryBot.create(:person, :with_consumer_role)}
  let!(:user2) { FactoryBot.create(:user, :person => person10, oim_id: '7734567899',email: "thisshouldnot@behappening.com") }
  let!(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person10) }
  let!(:person20) do
    per = FactoryBot.create(:person, :with_consumer_role, dob: Date.today - 30.years)
    person10.ensure_relationship_with(per, 'spouse')
    person10.save!
    per
  end
  let!(:family_member_20) { FactoryBot.create(:family_member, person: person20, family: family2)}
  let!(:person30) do
    per = FactoryBot.create(:person, :with_consumer_role, dob: Date.today - 10.years)
    person10.ensure_relationship_with(per, 'child')
    person10.save!
    per
  end
  let!(:family_member_30) { FactoryBot.create(:family_member, person: person30, family: family2)}
  let!(:person40) do
    per = FactoryBot.create(:person, :with_consumer_role, dob: Date.today - 10.years)
    person10.ensure_relationship_with(per, 'child')
    person10.save!
    per
  end
  let!(:family_member_40) { FactoryBot.create(:family_member, person: person40, family: family2)}
  let(:family_id2) { family2.id}
  let(:application20) { FactoryBot.create(:application, family: family2, aasm_state: "draft", effective_on: effective_on, application_period: application_period)}

  before do
    allow(person).to receive(:financial_assistance_identifier).and_return(family_id)
    sign_in(user)
    family.primary_person.consumer_role.move_identity_documents_to_verified
  end

  context "GET copy" do
    context "when there is not response from eligibility service" do
      let(:current_hbx_profile) { OpenStruct.new(under_open_enrollment?: true) }

      before do
        FinancialAssistance::Application.where(family_id: family_id).each {|app| app.update_attributes(aasm_state: "determined")}
        allow(HbxProfile).to receive(:current_hbx).and_return(current_hbx_profile)
      end

      it 'should copy applicant and redirect to financial assistance application edit path unless iap_year_selection enabled' do
        skip "skipped: iap_year_selection enabled" if FinancialAssistanceRegistry[:iap_year_selection].enabled?

        get :copy, params: { id: application.id }
        existing_app_ids = [application.id, application2.id]
        copy_app = FinancialAssistance::Application.where(family_id: family_id).reject {|app| existing_app_ids.include? app.id}.first
        expect(response).to redirect_to(edit_application_path(copy_app.id))
      end

      it 'should copy applicant and redirect to financial assistance assistance year select path if iap_year_selection enabled' do
        skip "skipped: iap_year_selection not enabled" unless FinancialAssistanceRegistry[:iap_year_selection].enabled?

        get :copy, params: { id: application.id }
        existing_app_ids = [application.id, application2.id]
        copy_app = FinancialAssistance::Application.where(family_id: family_id).reject {|app| existing_app_ids.include? app.id}.first
        expect(response).to redirect_to(application_year_selection_application_path(copy_app.id))
      end
    end

    context "when there is response from eligibility service" do
      include ::L10nHelper
      include ActionView::Helpers::TranslationHelper

      before do
        allow(controller).to receive(:call_service)
        controller.instance_variable_set(:@assistance_status, false)
        controller.instance_variable_set(:@message, "101")
        get :copy, params: { id: application.id }
      end

      let(:message) {l10n("faa.acdes_lookup")}

      it 'should not copy applicant and redirect to financial_assistance_applications_path' do
        expect(response).to redirect_to(applications_path)
      end

      it 'should not copy applicant and throw message' do
        expect(flash[:error].to_s).to match(message)
      end
    end

    context 'broker logged in' do
      let!(:broker_user) { FactoryBot.create(:user, :person => writing_agent.person, roles: ['broker_role', 'broker_agency_staff_role']) }
      let(:broker_agency_profile) { FactoryBot.build(:benefit_sponsors_organizations_broker_agency_profile, market_kind: :both) }

      let(:writing_agent) do
        FactoryBot.create(:broker_role, benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id, aasm_state: "active")
      end

      let(:assister)  do
        assister = FactoryBot.build(:broker_role, benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id, npn: "SMECDOA00", aasm_state: "active")
        assister.save(validate: false)
        assister
      end
      let(:user) { broker_user }
      let(:current_hbx_profile) { OpenStruct.new(under_open_enrollment?: true) }

      before do
        FinancialAssistance::Application.where(family_id: family_id).each {|app| app.update_attributes(aasm_state: "determined")}
        allow(HbxProfile).to receive(:current_hbx).and_return(current_hbx_profile)
        family.primary_person.consumer_role.move_identity_documents_to_verified
      end

      context 'hired by family' do
        before(:each) do
          family.broker_agency_accounts << BenefitSponsors::Accounts::BrokerAgencyAccount.new(benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id,
                                                                                              writing_agent_id: writing_agent.id,
                                                                                              start_on: Time.now,
                                                                                              is_active: true)
          family.reload
        end

        it "should render" do
          skip "skipped: iap_year_selection enabled" if FinancialAssistanceRegistry[:iap_year_selection].enabled?

          get :copy, params: { id: application.id }, session: { person_id: family.primary_person.id }
          existing_app_ids = [application.id, application2.id]
          copy_app = FinancialAssistance::Application.where(family_id: family_id).reject {|app| existing_app_ids.include? app.id}.first
          expect(response).to redirect_to(edit_application_path(copy_app.id))
        end
      end

      context 'not hired by family' do
        it "should render" do
          skip "skipped: iap_year_selection enabled" if FinancialAssistanceRegistry[:iap_year_selection].enabled?

          get :copy, params: { id: application.id }, session: { person_id: family.primary_person.id }
          expect(response).to have_http_status(:redirect)
          expect(flash[:error]).to eq('Access not allowed for financial_assistance/application_policy.copy?, (Pundit policy)')
        end
      end
    end
  end
end

def setup_faa_data
  FinancialAssistance::Application.all.each do |faa|
    faa.applicants.each do |appl|
      params = {gender: 'female', dob: Date.today - 30.years}
      appl.update_attributes!(params)
    end
  end
end

def main_app
  Rails.application.class.routes.url_helpers
end
