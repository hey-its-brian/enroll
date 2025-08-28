# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insured::IndividualMarket::ApplicantsController, dbclean: :after_each, type: :controller do
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, first_name: "John", last_name: "Smith") }
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application) do
    app = FactoryBot.create(:individual_market_application,
                            :initial,
                            family: family,
                            applicants: [
                              FactoryBot.build(:individual_market_applicant,
                                               :with_demographics,
                                               :with_eligibilities,
                                               :with_phone_number,
                                               :with_email,
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

  let(:applicant) { application.primary_applicant }

  let(:primary_applicant_params) do
    {
      applicant: {
        is_dependent: "false",
        is_primary_applicant: "true",
        person_name_attributes: {
          given_name: applicant.person_name.given_name,
          family_name: applicant.person_name.family_name
        },
        demographics_attributes: {
          dob: Date.strptime(applicant.demographics.dob.to_s, "%m/%d/%Y").strftime("%Y-%m-%d"),
          gender: applicant.demographics.gender,
          ssn: "263542644",
          encrypted_ssn: applicant.demographics.encrypted_ssn,
          no_ssn: 0,
          us_citizen: 'true',
          naturalized_citizen: 'false',
          eligible_immigration_status: 'false',
          indian_tribe_member: 'false',
          tribal_state: '',
          tribe_codes: [],
          is_incarcerated: 'true',
          ethnicity: []
        },
        is_applying_coverage: applicant.is_applying_coverage,
        age_off_excluded: "true",
        address_same_as_primary: applicant.address_same_as_primary,
        addresses_attributes: { :'0' => { kind: 'home',
                                          address_1: '123 Main St',
                                          address_2: '',
                                          city: 'Anytown',
                                          state: 'CA',
                                          zip: '12345',
                                          county: 'Any County',
                                          _destroy: 'false'}}
      },
      application_id: application.id,
      id: applicant.id
    }
  end

  let(:dependent_params) do
    {
      applicant: {
        is_dependent: 'true',
        is_primary_applicant: 'false',
        person_name_attributes: {
          given_name: "dependent",
          family_name: "jones"
        },
        demographics_attributes: {
          dob: Date.strptime(applicant.demographics.dob.to_s, "%m/%d/%Y").strftime("%Y-%m-%d"),
          gender: applicant.demographics.gender,
          no_ssn: 1,
          us_citizen: 'true',
          naturalized_citizen: 'false',
          eligible_immigration_status: 'false',
          indian_tribe_member: 'false',
          tribal_state: '',
          tribe_codes: [],
          is_incarcerated: 'true',
          ethnicity: []
        },
        relationship: "spouse",
        is_applying_coverage: 'true',
        age_off_excluded: "true",
        address_same_as_primary: 'true'
      },
      application_id: application.id
    }
  end

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
    [:js, :json].each do |format|
      it "returns 406 for #{format} format" do
        sign_in user
        base_params = { application_id: application.id }
        base_params[:id] = applicant.id unless [:index, :new].include?(action)
        params = base_params.merge(format: format)

        if method == :get
          get action, params: params
        else
          post action, params: params.merge(valid_params)
        end
        expect(response.status).to eq(406)
      end
    end
  end

  # to locally test the endpoints, you can pass in the action_name as a parameter
  # e.g. it_behaves_like "application endpoints", :authorized, :index
  # make sure to return to :all after testing the endpoints
  shared_examples_for "application endpoints" do |authorization_type, action_name|

    if [:all, :index].include?(action_name)
      describe "GET index" do
        before { get :index, params: { application_id: application.id, id: applicant.id } }

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

          it "renders the index template" do
            expect(response).to render_template(:index)
          end

          it_behaves_like "html only endpoint", :index, :get
        end
      end
    end

    if [:all, :show].include?(action_name)
      describe "GET show" do
        before { get :show, params: { application_id: application.id, id: applicant.id } }

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

          it "renders the show template" do
            expect(response).to render_template(:show)
          end

          it_behaves_like "html only endpoint", :show, :get
        end
      end
    end

    if [:all, :new].include?(action_name)
      describe "GET new" do
        before { get :new, params: { application_id: application.id } }

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

          it "assigns @applicant" do
            expect(assigns(:applicant)).to be_a(::Forms::IndividualMarket::Applicant)
          end

          it "assigns @person_name_form" do
            expect(assigns(:person_name_form)).to be_a(::Forms::IndividualMarket::PersonNameForm)
          end

          it "assigns @demographics_form" do
            expect(assigns(:demographics_form)).to be_a(::Forms::IndividualMarket::DemographicsForm)
          end

          it "assigns @immigration_information_form" do
            expect(assigns(:immigration_information_form)).to be_a(::Forms::IndividualMarket::ImmigrationInformationForm)
          end

          it "assigns @address_forms" do
            expect(assigns(:address_forms)).to be_an(Array)
            expect(assigns(:address_forms).first).to be_a(::Forms::Locations::AddressForm)
          end

          it "renders the new template" do
            expect(response).to render_template(:new)
          end

          it_behaves_like "html only endpoint", :new, :get
        end
      end
    end

    if [:all, :create].include?(action_name)
      describe "POST create" do
        if authorization_type == :authorized

          context "when the applicant is saved" do
            before do
              @applicants_count = application.applicants.count
              post :create, params: dependent_params
              application.reload
            end

            it "assigns @applicant" do
              expect(assigns(:applicant)).to be_a(::Forms::IndividualMarket::Applicant)
            end

            it "creates a new applicant" do
              expect(application.applicants.count).to eq(@applicants_count + 1)
            end

            it "redirects to the applicants index page" do
              expect(response).to redirect_to(insured_individual_market_application_applicants_path(application))
            end

            it "does not have a flash error" do
              expect(flash[:error]).to be_nil
            end
          end

          context "when the applicant is not saved" do
            before do
              post :create, params: { application_id: application.id, applicant: { first_name: "John", last_name: "Smith" } }
            end

            it "sets a flash message if the applicant is not saved" do
              post :create, params: { application_id: application.id, applicant: { first_name: "John", last_name: "Smith" } }
              expect(flash[:error]).to include("Failed to create applicant due to response:")
            end
          end
        end
      end
    end

    if [:all, :edit].include?(action_name)
      describe "GET edit" do
        before { get :edit, params: { application_id: application.id, id: applicant.id } }

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

          it "assigns @applicant" do
            expect(assigns(:applicant)).to eq(application.primary_applicant)
          end

          it "renders the edit template" do
            expect(response).to render_template(:new)
          end

          it_behaves_like "html only endpoint", :edit, :get
        end
      end
    end

    if [:all, :update].include?(action_name)
      describe "POST update" do
        if authorization_type == :authorized

          context "when the applicant is saved" do
            before do
              post :update, params: primary_applicant_params
              applicant.reload
            end

            it "assigns @applicant" do
              expect(assigns(:applicant)).to be_a(::Forms::IndividualMarket::Applicant)
            end

            it "updates the applicant" do
              expect(applicant.demographics.is_incarcerated).to eq(true)
            end

            it "does not have a flash error" do
              expect(flash[:error]).to be_nil
            end

            it "redirects to the applicants index page" do
              expect(response).to redirect_to(insured_individual_market_application_applicants_path(application))
            end
          end

          context "when the applicant is not saved" do
            before do
              post :update, params: { application_id: application.id, id: applicant.id, applicant: { first_name: "John", last_name: "Smith" } }
            end

            it "sets a flash message if the applicant is not saved" do
              expect(flash[:error]).to include("Failed to update applicant due to")
            end

            it "redirects to the applicants index page" do
              expect(response).to redirect_to(insured_individual_market_application_applicants_path(application))
            end
          end
        end
      end
    end

    if [:all, :destroy].include?(action_name)
      describe "DELETE destroy" do
        let(:dependent_applicant) do
          FactoryBot.build(:individual_market_applicant,
                           :with_demographics,
                           :with_eligibilities,
                           :dependent,
                           application: application)
        end

        before do
          application.applicants << dependent_applicant
          application.save
        end

        if authorization_type == :authorized
          it "deletes the dependent applicant" do
            delete :destroy, params: { application_id: application.id, id: dependent_applicant.id }
            application.reload
            expect(application.applicants.where(id: dependent_applicant.id).first).to be_nil
          end

          it "does not delete the primary applicant" do
            delete :destroy, params: { application_id: application.id, id: applicant.id }
            application.reload
            expect(application.applicants.where(id: applicant.id).first).to eq(applicant)
          end

          it 'destroys the dependents relationship' do
            delete :destroy, params: { application_id: application.id, id: dependent_applicant.id }
            application.reload
            expect(application.relationships.where(source_id: dependent_applicant.id).first).to be_nil
          end
        end
      end
    end

    if [:all, :update_preferences].include?(action_name)
      describe "POST update_preferences" do
        if authorization_type == :authorized
          let(:base_preferences_params) do
            {
              application_id: application.id,
              applicant_id: applicant.id,
              individual_market_applicant: { contact_method: ["Email"] }
            }
          end

          before do
            applicant.phones.create(kind: "mobile", number: "2234567890")
            applicant.emails.create(kind: "work", address: "example@example.com")
          end

          context "when SMS notifications feature is enabled" do
            before do
              allow(EnrollRegistry).to receive(:feature_enabled?).with(:enroll_sms_notifications).and_return(true)
            end

            context "when applicant saves successfully with enhanced context" do
              before do
                allow_any_instance_of(::IndividualMarket::Applicant).to receive(:save).with(context: :enhanced_contact_preferences).and_return(true)
              end

              it "saves with enhanced_contact_preferences context" do
                expect_any_instance_of(::IndividualMarket::Applicant).to receive(:save).with(context: :enhanced_contact_preferences)
                post :update_preferences, params: base_preferences_params
              end

              it "redirects to review page on successful save" do
                post :update_preferences, params: base_preferences_params
                expect(response).to redirect_to(review_insured_individual_market_application_path(application))
              end
            end

            context "when applicant fails validation with enhanced context" do
              before do
                allow_any_instance_of(::IndividualMarket::Applicant).to receive(:save).with(context: :enhanced_contact_preferences).and_return(false)
                allow_any_instance_of(::IndividualMarket::Applicant).to receive_message_chain(:errors, :full_messages, :join).and_return("Phone number is required for SMS notifications")
              end

              it "redirects back to preferences with validation error" do
                post :update_preferences, params: base_preferences_params
                expect(response).to redirect_to(preferences_insured_individual_market_application_path(application))
                expect(flash[:error]).to eq("Phone number is required for SMS notifications")
              end
            end
          end

          context "when SMS notifications feature is disabled" do
            before do
              allow(EnrollRegistry).to receive(:feature_enabled?).with(:enroll_sms_notifications).and_return(false)
              allow_any_instance_of(::IndividualMarket::Applicant).to receive(:save).with(context: nil).and_return(true)
            end

            it "saves without enhanced context" do
              expect_any_instance_of(::IndividualMarket::Applicant).to receive(:save).with(context: nil)
              post :update_preferences, params: base_preferences_params
            end

            it "redirects to review page" do
              post :update_preferences, params: base_preferences_params
              expect(response).to redirect_to(review_insured_individual_market_application_path(application))
            end
          end

          it "transforms the preferences if it is an array" do
            post :update_preferences, params: base_preferences_params
            applicant.reload
            expect(applicant.contact_method).to include("Only Electronic communications")
          end

          it "does not transform the preferences if it is not an array" do
            post :update_preferences, params: {
              application_id: application.id,
              applicant_id: applicant.id,
              individual_market_applicant: { contact_method: "Email" }
            }
            applicant.reload
            expect(applicant.contact_method).not_to eq("Email")
          end

          it "only updates fields from the permitted params" do
            post :update_preferences, params: {
              application_id: application.id,
              applicant_id: applicant.id,
              individual_market_applicant: {
                contact_method: ["Email", "Mail", "Text"],
                is_homeless: true
              }
            }
            applicant.reload
            expect(applicant.contact_method).to include("Paper, Electronic and Text Message communications")
            expect(applicant.is_homeless).to be_falsey
          end

          context "when there is a phone change" do
            let(:phone_params) do
              {
                phones_attributes: {
                  "0" => { kind: "home", full_phone_number: "(438) 763-7476", id: applicant.phones.first.id, _destroy: "false" }
                }
              }
            end

            it "updates the phone if the number changed" do
              post :update_preferences, params: {
                application_id: application.id,
                applicant_id: applicant.id,
                individual_market_applicant: phone_params
              }
              applicant.reload
              expect(applicant.phones.count).to eq(1)
              expect(applicant.phones.first.number).to eq("7637476")
            end

            it "destroys the phone if marked for destruction" do
              phone_params[:phones_attributes]["0"][:_destroy] = "true"
              post :update_preferences, params: {
                application_id: application.id,
                applicant_id: applicant.id,
                individual_market_applicant: phone_params
              }
              applicant.reload
              expect(applicant.phones.count).to eq(0)
            end
          end

          context "when there is an email change" do
            let(:email_params) do
              {
                emails_attributes: {
                  "0" => { kind: "work", address: "test@test.com", id: applicant.work_email.id, _destroy: "false" }
                }
              }
            end

            it "updates the email if the address changed" do
              post :update_preferences, params: {
                application_id: application.id,
                applicant_id: applicant.id,
                individual_market_applicant: email_params
              }
              applicant.reload
              expect(applicant.work_email.address).to eq("test@test.com")
            end

            it "destroys the email if marked for destruction" do
              email_params[:emails_attributes]["0"][:_destroy] = "true"
              post :update_preferences, params: {
                application_id: application.id,
                applicant_id: applicant.id,
                individual_market_applicant: email_params
              }
              applicant.reload
              expect(applicant.work_email).to be_nil
            end
          end
        end
      end
    end

    if [:all, :show_ssn].include?(action_name)
      describe "GET show_ssn" do
        let(:ssn) { "123456789" }
        let(:formatted_ssn) { "123-45-6789" }

        if authorization_type.in?([:unauthorized, :unassociated])
          it "is not successful" do
            get :show_ssn, params: { application_id: application.id, id: applicant.id }
            expect(response).not_to have_http_status(200)
          end
        else
          it "returns the formatted SSN in JSON response" do
            applicant.demographics.update_attributes(ssn: ssn, no_ssn: 0)
            get :show_ssn, params: { application_id: application.id, id: applicant.id }
            expect(response).to have_http_status(200)
            parsed_response = JSON.parse(response.body)
            expect(parsed_response["payload"]).to eq(formatted_ssn)
            expect(parsed_response["status"]).to eq(200)
          end
        end
      end
    end
  end

  context "when user is not signed in" do
    it_behaves_like "application endpoints", :unauthorized, :all
  end

  context "when user does not own the application" do
    other_person = FactoryBot.create(:person, :with_consumer_role)
    other_person.consumer_role.move_identity_documents_to_verified
    User.where(email: "other_user@example.com").destroy_all
    other_user = FactoryBot.create(:user, person: other_person, email: "other_user@example.com", password: "1!2bthree456Df", password_confirmation: "1!2bthree456Df", oim_id: "1234567890")

    before do
      sign_in other_user
    end

    it_behaves_like "application endpoints", :unassociated, :all
  end

  context "when user owns the application" do
    before do
      sign_in user
    end

    it_behaves_like "application endpoints", :authorized, :all
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

    it_behaves_like "application endpoints", :authorized, :all
  end

  context 'when user is a broker who is not associated with the application' do
    before do
      sign_in broker_role_user
    end

    it_behaves_like "application endpoints", :unassociated, :all
  end

  context "when user is HBX staff" do
    let(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
    let(:permission) { FactoryBot.create(:permission, :super_admin) }
    let(:admin_user) { FactoryBot.create(:user, :with_hbx_staff_role, person: admin_person) }

    before do
      admin_person.hbx_staff_role.update!(permission_id: permission.id)
      sign_in admin_user
    end

    it_behaves_like "application endpoints", :authorized, :all
  end

  describe "feature flag behavior" do
    before do
      allow(EnrollRegistry[:qhp_application].feature).to receive(:is_enabled).and_return(false)
      sign_in user
    end

    it "returns 404 when feature is disabled" do
      get :index, params: { application_id: application.id, id: applicant.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "when application is not found" do
    before do
      sign_in user
      get :index, params: { application_id: "invalid_id", id: application.id }
    end

    it "redirects to root path" do
      expect(response).to have_http_status(:found) # 302 redirect
      expect(response).to redirect_to(root_path)
      expect(flash[:error]).to match(/Access not allowed/)
    end
  end
end
