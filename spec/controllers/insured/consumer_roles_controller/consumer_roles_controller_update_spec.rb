# frozen_string_literal: true

require "rails_helper"

RSpec.describe Insured::ConsumerRolesController do
  describe "PUT update, for an IVL market person with a consumer role" do
    let(:person_id) { "SOME PERSON ID" }
    let(:consumer_role_id) { "SOME CONSUMER ROLE ID" }
    let(:user) do
      instance_double(
        User,
        person: person,
        has_hbx_staff_role?: false
      )
    end
    let(:family) { instance_double(Family, id: family_id) }
    let(:family_id) { "SOME FAMILY ID" }
    let(:family_member) do
      instance_double(
        FamilyMember,
        person: dependent_person,
        family: family
      )
    end
    let(:person) do
      instance_double(
        Person,
        is_resident_role_active?: false,
        no_dc_address: false,
        has_multiple_roles?: false,
        id: person_id,
        agent?: false,
        first_name: "John",
        last_name: "Smith",
        ssn: "123",
        dob: TimeKeeper.date_of_record - 30.years
      )
    end
    let(:consumer_role) do
      double(
        person: person,
        policy_class: ConsumerRolePolicy
      )
    end

    let(:person_controller_parameters) do
      ActionController::Parameters.new(person_update_properties).permit!
    end

    before(:each) do
      sign_in(user)
      allow(ConsumerRole).to receive(:find).with(consumer_role_id).and_return(consumer_role)
      allow(consumer_role).to receive(:skip_consumer_role_callbacks=).and_return(true)
      allow(consumer_role).to receive(:update_by_person).with({"skip_person_updated_event_callback" => true, "skip_lawful_presence_determination_callbacks" => true}.merge(person_controller_parameters)).and_return(true)
      allow(EnrollRegistry[:mec_check].feature).to receive(:is_enabled).and_return(false)
      allow(EnrollRegistry[:shop_coverage_check].feature).to receive(:is_enabled).and_return(false)
      allow(person).to receive(:mec_check_eligible?).and_return(false)
    end

    describe "when the value for 'is_applying_coverage' is provided" do
      let(:is_applying_coverage_value) { "false" }
      let(:person_update_properties) do
        {
          "first_name" => "Person First Name",
          "is_applying_coverage" => is_applying_coverage_value
        }
      end

      it "updates the 'is_applying_coverage' value for the dependent" do
        expect(consumer_role).to receive(:update_attribute).with(:is_applying_coverage, is_applying_coverage_value).and_return(true)
        put :update, params: {id: consumer_role_id, person: person_update_properties, exit_after_method: true}
      end
    end

    describe "when the value for 'is_applying_coverage' is NOT provided" do
      let(:person_update_properties) do
        { "first_name" => "Person First Name" }
      end

      it "does not change the 'is_applying_coverage' value for the dependent" do
        expect(consumer_role).not_to receive(:update_attribute)
        put :update, params: {id: consumer_role_id, person: person_update_properties, exit_after_method: true}
      end
    end
  end

  describe "help_paying_coverage" do

    context 'when FAA feature enabled' do
      let(:user) { FactoryBot.create :user, :with_consumer_role }

      before do
        allow(EnrollRegistry[:aca_individual_market].feature).to receive(:is_enabled).and_return(true)
        allow(EnrollRegistry[:financial_assistance].feature).to receive(:is_enabled).and_return(true)
        allow(EnrollRegistry[:validate_quadrant].feature).to receive(:is_enabled).and_return(true)
        # allow(EnrollRegistry).to receive(:feature_enabled?).with(:location_residency_verification_type).and_return(true)
        allow(controller).to receive(:authorize).and_return(true)
        sign_in user
      end

      subject { get :help_paying_coverage }

      it 'renders help_paying_coverage template' do
        expect(subject).to render_template('insured/consumer_roles/help_paying_coverage')
      end
    end

    context 'when FAA feature disabled' do
      let(:user) { FactoryBot.create :user, :with_consumer_role }

      before do
        allow(EnrollRegistry[:aca_individual_market].feature).to receive(:is_enabled).and_return(true)
        allow(EnrollRegistry[:financial_assistance].feature).to receive(:is_enabled).and_return(false)
        allow(EnrollRegistry[:validate_quadrant].feature).to receive(:is_enabled).and_return(true)
        # allow(EnrollRegistry).to receive(:feature_enabled?).with(:location_residency_verification_type).and_return(true)
        sign_in user
      end

      subject { get :help_paying_coverage }

      it 'renders help_paying_coverage template' do
        expect(subject.status).to eq(404)
        expect(response.body).to include("The page you were looking for doesn't exist (404)")
      end
    end
  end

  describe "help_paying_for_coverage_response" do
    let(:user) { FactoryBot.create :user, :with_consumer_role }
    before { sign_in user }

    subject { get :help_paying_coverage_response, params: params }

    context "is_applying_for_assistance false" do
      let(:params) { { is_applying_for_assistance: false } }

      it 'redirects to insured_family_members_path' do
        expect(subject).to redirect_to(insured_family_members_path(consumer_role_id: user.person.consumer_role.id))
      end
    end

    context "is_applying_for_assistance true" do
      let(:current_hbx_profile) { OpenStruct.new(under_open_enrollment?: true) }
      let(:params) { { is_applying_for_assistance: true } }
      let(:result) { ::Dry::Monads::Result::Success.new(1) }

      context "iap year selection is enabled and IVL oe end date is in future" do
        before do
          allow(HbxProfile).to receive(:current_hbx).and_return(current_hbx_profile)
          allow(EnrollRegistry[:iap_year_selection].feature).to receive(:is_enabled).and_return(true)
          allow(TimeKeeper).to receive(:date_of_record).and_return(Date.new(TimeKeeper.date_of_record.year, 1, 1))
        end

        it "redirects to financial assistance's year selection page" do
          expect(Operations::FinancialAssistance::Apply).to receive(:new) do
            double(call: result)
          end

          expect(subject).to redirect_to('/financial_assistance/applications/1/application_year_selection')
        end
      end

      context "iap year selection is disabled and IVL oe end date is in future" do
        before do
          allow(EnrollRegistry[:iap_year_selection].feature).to receive(:is_enabled).and_return(false)
          allow(TimeKeeper).to receive(:date_of_record).and_return(Date.new(TimeKeeper.date_of_record.year, 1, 1))
        end

        it "redirects to financial assistance's year selection page" do
          expect(Operations::FinancialAssistance::Apply).to receive(:new) do
            double(call: result)
          end

          expect(subject).to redirect_to('/financial_assistance/applications/1/application_checklist')
        end
      end
    end
  end

  describe 'GET #help_paying_coverage_response' do
    let(:primary_person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:new_family) { FactoryBot.create(:family, :with_primary_family_member, person: primary_person) }
    let(:application) { FinancialAssistance::Application.where(family_id: new_family.id, aasm_state: 'draft').first }
    let(:hbx_profile) do
      FactoryBot.create(
        :hbx_profile,
        :normal_ivl_open_enrollment,
        us_state_abbreviation: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item,
        cms_id: "#{EnrollRegistry[:enroll_app].setting(:state_abbreviation).item.upcase}0"
      )
    end
    let(:ivl_product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, benefit_market_kind: :aca_individual) }

    before :each do
      sign_in user
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      hbx_profile.benefit_sponsorship.benefit_coverage_periods.each {|bcp| bcp.update_attributes!(slcsp_id: ivl_product.id)}
      new_family
      allow(new_family).to receive(:benchmark_product_id).and_return(ivl_product.id)
      session[:person_id] = primary_person.id
    end

    context 'when the logged in user is same as the consumer' do
      let(:user) { FactoryBot.create(:user, person: primary_person) }

      before do
        get :help_paying_coverage_response, params: {
          id: primary_person.id, is_applying_for_assistance: true
        }
      end

      it 'returns success' do
        expect(response).to have_http_status(:redirect)
      end

      it 'creates a financial assistance application' do
        expect(application).to be_present
        expect(application.origin).to eq(:user)
        expect(application.generation_reason).to eq(:manual)
      end
    end

    context 'when the logged in user is Hbx Staff' do
      let(:hbx_person) { FactoryBot.create(:person) }
      let(:permission) { FactoryBot.create(:permission, :super_admin) }
      let(:hbx_staff) { FactoryBot.create(:hbx_staff_role, person: hbx_person, permission_id: permission.id) }
      let(:user) { FactoryBot.create(:user, person: hbx_staff.person) }

      before do
        get :help_paying_coverage_response, params: {
          id: primary_person.id, is_applying_for_assistance: true
        }
      end

      it 'returns success' do
        expect(response).to have_http_status(:redirect)
      end

      it 'creates a financial assistance application' do
        expect(application).to be_present
        expect(application.origin).to eq(:admin)
        expect(application.generation_reason).to eq(:manual)
      end
    end

    context 'when the logged in user is an active broker' do
      let(:broker_role) { FactoryBot.create(:broker_role, aasm_state: 'active', benefit_sponsors_broker_agency_profile_id: BSON::ObjectId.new) }
      let(:user) { FactoryBot.create(:user, person: broker_role.person) }

      before do
        new_family.broker_agency_accounts.create!(
          is_active: true,
          writing_agent_id: broker_role.id,
          start_on: TimeKeeper.date_of_record,
          benefit_sponsors_broker_agency_profile_id: BSON::ObjectId.new
        )

        get :help_paying_coverage_response, params: {
          id: primary_person.id, is_applying_for_assistance: true
        }
      end

      it 'returns success' do
        expect(response).to have_http_status(:redirect)
      end

      it 'creates a financial assistance application' do
        expect(application).to be_present
        expect(application.origin).to eq(:broker)
        expect(application.generation_reason).to eq(:manual)
      end
    end

    context 'when the logged in user is an active broker staff' do
      let(:market_kind) { :individual }
      let(:broker_person) { FactoryBot.create(:person) }
      let(:broker_role) { FactoryBot.create(:broker_role, person: broker_person) }
      let(:broker_staff_person) { FactoryBot.create(:person) }
      let(:broker_staff_state) { 'active' }
      let(:broker_staff) do
        FactoryBot.create(
          :broker_agency_staff_role,
          person: broker_staff_person,
          aasm_state: broker_staff_state,
          benefit_sponsors_broker_agency_profile_id: broker_agency_id
        )
      end
      let(:broker_staff_user) { FactoryBot.create(:user, person: broker_staff_person) }

      let(:site) do
        FactoryBot.create(
          :benefit_sponsors_site,
          :with_benefit_market,
          :as_hbx_profile,
          site_key: ::EnrollRegistry[:enroll_app].settings(:site_key).item
        )
      end

      let(:broker_agency_organization) { FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_broker_agency_profile, site: site) }
      let(:broker_agency_profile) { broker_agency_organization.broker_agency_profile }
      let(:broker_agency_id) { broker_agency_profile.id }
      let(:baa_active) { true }
      let(:user) { broker_staff_user }

      let(:broker_agency_account) do
        new_family.broker_agency_accounts.create!(
          benefit_sponsors_broker_agency_profile_id: broker_agency_id,
          writing_agent_id: broker_role.id,
          is_active: baa_active,
          start_on: TimeKeeper.date_of_record
        )
      end

      before do
        broker_role.update_attributes!(benefit_sponsors_broker_agency_profile_id: broker_agency_id)
        broker_person.create_broker_agency_staff_role(
          benefit_sponsors_broker_agency_profile_id: broker_role.benefit_sponsors_broker_agency_profile_id
        )
        broker_agency_profile.update_attributes!(primary_broker_role_id: broker_role.id, market_kind: market_kind)
        broker_role.approve!
        broker_agency_account
        broker_staff

        get :help_paying_coverage_response, params: {
          id: primary_person.id, is_applying_for_assistance: true
        }
      end

      it 'returns success' do
        expect(response).to have_http_status(:redirect)
      end

      it 'creates a financial assistance application' do
        expect(application).to be_present
        expect(application.origin).to eq(:broker_staff)
        expect(application.generation_reason).to eq(:manual)
      end
    end

    # context 'when the logged in user is an active assister' do
    # end
  end
end
