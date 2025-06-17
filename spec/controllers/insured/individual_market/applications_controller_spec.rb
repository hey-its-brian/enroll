# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insured::IndividualMarket::ApplicationsController, dbclean: :after_each, type: :controller do

  # Create person and user since they are critical for auth testing
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, first_name: "John", last_name: "Smith") }
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:current_state) { :initial }
  # Only create the application since it's central to our tests
  let(:application) do
    app = FactoryBot.create(:individual_market_application,
                            current_state: current_state,
                            family: family,
                            applicants: [
                              FactoryBot.build(:individual_market_applicant,
                                               :with_demographics,
                                               :with_eligibilities,
                                               family_member_id: family.primary_family_member.id,
                                               is_primary_applicant: true,
                                               person_name: {
                                                 given_name: person.first_name,
                                                 family_name: person.last_name
                                               })
                            ])
    app.save!
    app
  end

  let(:valid_params) do
    {
      terms_check: "true",
      first_name: person.first_name,
      last_name: person.last_name
    }
  end

  let(:operation) { instance_double(Operations::IndividualMarket::SubmitAndDetermineApplication) }

  let(:site) { FactoryBot.create(:benefit_sponsors_site, :with_benefit_market, :as_hbx_profile, :cca) }
  let(:broker_agency_profile) { FactoryBot.create(:benefit_sponsors_organizations_broker_agency_profile, market_kind: :individual) }
  let!(:broker_role) { FactoryBot.create(:broker_role, benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id, aasm_state: :active) }
  let!(:broker_role_user) {FactoryBot.create(:user, :person => broker_role.person, roles: ['broker_role'])}

  let!(:broker_agency_staff_role) { FactoryBot.create(:broker_agency_staff_role, benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id, aasm_state: 'active')}
  let!(:broker_agency_staff_user) {FactoryBot.create(:user, :person => broker_agency_staff_role.person, roles: ['broker_agency_staff_role'])}

  before(:all) do
    DatabaseCleaner.clean
  end

  before do
    allow(EnrollRegistry[:qhp_application].feature).to receive(:is_enabled).and_return(true)
    allow(EnrollRegistry[:bs4_consumer_flow].feature).to receive(:is_enabled).and_return(true)
    person.consumer_role.move_identity_documents_to_verified
  end

  shared_examples_for "html only endpoint" do |action, method|
    [:json, :js].each do |format|
      it "returns 406 for #{format} format" do
        sign_in user
        params = { id: application.id, format: format }
        if method == :get
          get action, params: params
        else
          post action, params: params.merge(valid_params)
        end
        expect(response.status).to eq(406)
      end
    end
  end

  shared_examples_for "application endpoints" do |authorization_type|
    describe "GET review" do
      before { get :review, params: { id: application.id } }

      case authorization_type
      when :unauthorized
        it "redirects to sign in" do
          expect(response).to redirect_to(new_user_session_path)
        end
      when :unassociated
        it "redirects with access denied" do
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Access not allowed/)
        end
      else
        it "returns success" do
          expect(response).to be_successful
        end

        it "assigns @application" do
          expect(assigns(:application)).to eq application
        end

        it "renders the review template" do
          expect(response).to render_template(:review)
        end

        it_behaves_like "html only endpoint", :review, :get
      end
    end

    describe "GET preferences" do
      before { get :preferences, params: { id: application.id } }

      case authorization_type
      when :unauthorized
        it "redirects to sign in" do
          expect(response).to redirect_to(new_user_session_path)
        end
      when :unassociated
        it "redirects with access denied" do
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Access not allowed/)
        end
      else
        it "returns success" do
          expect(response).to be_successful
        end

        it "assigns @applicant" do
          expect(assigns(:applicant)).to eq(application.primary_applicant)
        end

        it "renders the preferences template" do
          expect(response).to render_template(:preferences)
        end

        it_behaves_like "html only endpoint", :preferences, :get
      end
    end

    describe "GET attestation" do
      before { get :attestation, params: { id: application.id } }

      case authorization_type
      when :unauthorized
        it "redirects to sign in" do
          expect(response).to redirect_to(new_user_session_path)
        end
      when :unassociated
        it "redirects with access denied" do
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Access not allowed/)
        end
      else
        it "returns success" do
          expect(response).to be_successful
        end

        it "assigns @application" do
          expect(assigns(:application)).to eq application
        end

        it "renders the attestation template" do
          expect(response).to render_template(:attestation)
        end

        it_behaves_like "html only endpoint", :attestation, :get
      end
    end

    describe "POST submit" do
      before do
        allow(Operations::IndividualMarket::SubmitAndDetermineApplication).to receive(:new).and_call_original
      end

      case authorization_type
      when :unauthorized
        it "redirects to sign in" do
          post :submit, params: { id: application.id }
          expect(response).to redirect_to(new_user_session_path)
        end
      when :unassociated
        it "redirects with access denied" do
          post :submit, params: { id: application.id }
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Access not allowed/)
        end
      else
        context "with valid attestation parameters" do
          before do
            post :submit, params: {
              id: application.id,
              terms_check: "true",
              first_name: application.primary_applicant.person_name.given_name,
              last_name: application.primary_applicant.person_name.family_name
            }
          end

          it "redirects to eligibility results" do
            expect(response).to redirect_to(eligibility_results_insured_individual_market_application_path(application, internal: true))
          end

          it "sets submitted_at timestamp on application" do
            expect(application.reload.submitted_at).to be_present
          end
        end

        context "with invalid attestation parameters" do
          before do
            post :submit, params: { id: application.id }.merge(valid_params.merge(terms_check: "false"))
          end

          it "redirects back to application with error" do
            expect(response).to redirect_to(insured_individual_market_application_path(application))
            expect(flash[:error]).to eq("Invalid attestation")
          end
        end

        it_behaves_like "html only endpoint", :submit, :post
      end
    end

    describe "GET eligibility_results" do
      before { get :eligibility_results, params: { id: application.id } }

      case authorization_type
      when :unauthorized
        it "redirects to sign in" do
          expect(response).to redirect_to(new_user_session_path)
        end
      when :unassociated
        it "redirects with access denied" do
          expect(response).to redirect_to(root_path)
          expect(flash[:error]).to match(/Access not allowed/)
        end
      else
        it "returns success" do
          expect(response).to be_successful
        end

        it "assigns @application" do
          expect(assigns(:application)).to eq application
        end

        it "renders the eligibility_results template" do
          expect(response).to render_template(:eligibility_results)
        end

        it_behaves_like "html only endpoint", :eligibility_results, :get
      end
    end
  end

  shared_examples_for "admin only endpoints" do |authorization_type|

    describe "GET eligibility_criteria" do
      if authorization_type == :authorized
        context "when application is still in initial state" do
          before do
            application.update_attributes(current_state: :initial)
            application.reload
            allow(application).to receive(:is_determined?).and_return(false)
            get :eligibility_criteria, params: { id: application.id }
          end

          it "redirects to review path" do
            expect(response).to redirect_to(review_insured_individual_market_application_path(application))
          end
        end
      end

      context "when application is in determined state" do
        before do
          application.update_attributes(current_state: :determined)
          application.reload
          allow(application).to receive(:is_determined?).and_return(true)
          get :eligibility_criteria, params: { id: application.id }
        end

        case authorization_type
        when :unauthorized
          it "redirects to sign in" do
            expect(response).to redirect_to(new_user_session_path)
          end
        when :unassociated
          it "redirects with access denied" do
            expect(response).to redirect_to(root_path)
            expect(flash[:error]).to match(/Access not allowed/)
          end
        else
          it "returns success" do
            expect(response).to be_successful
          end

          it "assigns @application" do
            expect(assigns(:application)).to eq application
          end

          it "renders the eligibility_criteria template" do
            expect(response).to render_template(:eligibility_criteria)
          end

          it_behaves_like "html only endpoint", :eligibility_criteria, :get
        end
      end
    end
  end

  context "when user is not signed in" do
    it_behaves_like "application endpoints", :unauthorized
    it_behaves_like "admin only endpoints", :unauthorized
  end

  context "when user does not own the application" do
    other_person = FactoryBot.create(:person, :with_consumer_role)
    other_person.consumer_role.move_identity_documents_to_verified
    User.where(email: "other_user@example.com").destroy_all
    other_user = FactoryBot.create(:user, person: other_person, email: "other_user@example.com", password: "1!2bthree456Df", password_confirmation: "1!2bthree456Df", oim_id: "1234567890")

    before do
      sign_in other_user
    end

    it_behaves_like "application endpoints", :unassociated
    it_behaves_like "admin only endpoints", :unassociated
  end

  context "when user owns the application" do
    before do
      sign_in user
    end

    it_behaves_like "application endpoints", :authorized
    it_behaves_like "admin only endpoints", :unassociated
  end

  context "when user is an associated broker" do
    before do
      family.broker_agency_accounts << BenefitSponsors::Accounts::BrokerAgencyAccount.new(benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id,
                                                                                          start_on: Time.now,
                                                                                          writing_agent_id: broker_role.id,
                                                                                          is_active: true)
      sign_in broker_role_user
      family.reload
    end

    it_behaves_like "application endpoints", :authorized
    it_behaves_like "admin only endpoints", :unassociated
  end

  context 'when user is a broker who is not associated with the application' do
    before do
      sign_in broker_role_user
    end

    it_behaves_like "application endpoints", :unassociated
    it_behaves_like "admin only endpoints", :unassociated
  end

  context "when user is HBX staff" do
    let(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
    let(:permission) { FactoryBot.create(:permission, :super_admin) }
    let(:admin_user) { FactoryBot.create(:user, :with_hbx_staff_role, person: admin_person) }

    before do
      admin_person.hbx_staff_role.update!(permission_id: permission.id)
      sign_in admin_user
    end

    it_behaves_like "application endpoints", :authorized
    it_behaves_like "admin only endpoints", :authorized
  end

  describe "feature flag behavior" do
    before do
      allow(EnrollRegistry[:qhp_application].feature).to receive(:is_enabled).and_return(false)
      sign_in user
    end

    it "returns 404 when feature is disabled" do
      get :review, params: { id: application.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "when application is not found" do
    before do
      sign_in user
      get :review, params: { id: "invalid_id" }
    end

    it "redirects to root path" do
      expect(response).to have_http_status(:found) # 302 redirect
      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to match(/Access not allowed/)
    end
  end

  describe 'GET #copy' do
    let(:new_user)          { FactoryBot.create(:user, person: new_person) }
    let(:new_person)        { FactoryBot.create(:person) }
    let(:new_consumer_role) { FactoryBot.create(:consumer_role, person: new_person, identity_validation: 'valid') }
    let(:new_family)        { FactoryBot.create(:family, :with_primary_family_member, person: new_consumer_role.person) }
    let(:new_application)   { FactoryBot.create(:individual_market_application, current_state: current_state, family: new_family) }
    let(:current_state)     { :determined }

    before :each do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    end

    context 'when:
      - authorized user is signed in
      - valid application exists
      ' do

      let(:new_app) do
        IndividualMarket::Application.find_by(
          predecessor_id: new_application.id,
          family_id: new_family.id
        )
      end

      before do
        sign_in new_user
      end

      context "without applicant or preferences params" do
        before { get :copy, params: { id: new_application.id }, session: { person_id: new_family.primary_person.id }}

        it 'redirects to the applicants index page of the copied application' do
          expect(response).to redirect_to(insured_individual_market_application_applicants_path(application_id: new_app.id))
        end

        it 'creates a new application with copied attributes' do
          expect(new_app).to be_persisted
          expect(new_app.initial?).to be_truthy
          expect(new_app.predecessor_id).to eq(new_application.id)
          expect(new_app.family).to eq(new_family)
        end
      end

      context "with applicant param" do
        before { get :copy, params: { id: new_application.id, applicant: "12345" }, session: { person_id: new_family.primary_person.id }}

        it 'redirects to the applicants index page of the copied application with an applicant param' do
          expect(response).to redirect_to(insured_individual_market_application_applicants_path(application_id: new_app.id, applicant: "12345"))
        end
      end

      context "with preferences param" do
        before { get :copy, params: { id: new_application.id, preferences: true }, session: { person_id: new_family.primary_person.id }}

        it 'redirects to the preferences page of the copied application with a preferences param' do
          expect(response).to redirect_to(preferences_insured_individual_market_application_path(new_app.id))
        end
      end
    end

    context 'when:
      - user is signed in
      - application with invalid current state
      ' do

      let(:current_state) { :initial }

      before do
        sign_in new_user
        get :copy, params: { id: new_application.id }, session: { person_id: new_family.primary_person.id }
      end

      it 'redirects to the sbm applications index page' do
        expect(response).to redirect_to(insured_sbm_applications_path)
        expect(flash[:error]).to eq(
          "Application cannot be copied as it is not in one of the #{::IndividualMarket::Application::COPYABLE_STATES.join(', ')} states"
        )
      end
    end
  end
end