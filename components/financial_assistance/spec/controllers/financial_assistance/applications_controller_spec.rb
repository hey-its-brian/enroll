# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::ApplicationsController, dbclean: :after_each, type: :controller do
  routes { FinancialAssistance::Engine.routes }

  after :all do
    DatabaseCleaner.clean
  end

  let(:person1) { FactoryBot.create(:person, :with_consumer_role)}
  let!(:user) { FactoryBot.create(:user, :person => person1) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }
  let!(:person2) do
    per = FactoryBot.create(:person, :with_consumer_role, dob: Date.today - 30.years)
    person1.ensure_relationship_with(per, 'spouse')
    person1.save!
    per
  end
  let!(:family_member_2) { FactoryBot.create(:family_member, person: person2, family: family)}
  let!(:person3) do
    per = FactoryBot.create(:person, :with_consumer_role, dob: Date.today - 10.years)
    person1.ensure_relationship_with(per, 'child')
    person1.save!
    per
  end
  let!(:family_member_3) { FactoryBot.create(:family_member, person: person3, family: family)}
  let!(:person4) do
    per = FactoryBot.create(:person, :with_consumer_role, dob: Date.today - 10.years)
    person1.ensure_relationship_with(per, 'child')
    person1.save!
    per
  end
  let!(:family_member_4) { FactoryBot.create(:family_member, person: person4, family: family)}

  let(:family_id) { family.id}
  let(:effective_on) { TimeKeeper.date_of_record.next_month.beginning_of_month }
  let(:application_period) {effective_on.beginning_of_year..effective_on.end_of_year}

  before do
    family.primary_person.consumer_role.move_identity_documents_to_verified
  end

  describe "GET index" do
    before(:each) do
      sign_in user
    end

    it "assigns @applications" do
      application = FinancialAssistance::Application.create!(family_id: family_id)
      get :index
      expect(assigns(:applications).to_a).to eq([application])
    end

    it "renders the index template" do
      get :index
      expect(response).to render_template("index")
    end

    context "when the request type is invalid" do
      it "renders the index template" do
        get :index, format: :json
        expect(response.status).to eq 406
        expect(response.body).to eq "{\"error\":\"Unsupported format\"}"
        expect(response.media_type).to eq "application/json"
      end

      it "renders the index template" do
        get :index, format: :fake
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
      end

      it "renders the index template" do
        get :index, format: :xml
        expect(response.status).to eq 406
        expect(response.body).to eq "<error>Unsupported format</error>"
      end
    end

    context 'for a person who exists in multiple families(with financial assistance applications)' do
      let!(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }
      let!(:application1) { FinancialAssistance::Application.create!(family_id: family_id) }
      let!(:application2) { FinancialAssistance::Application.create!(family_id: family2.id) }
      let!(:family_member_2_2) { FactoryBot.create(:family_member, person: person1, family: family2)}

      before do
        get :index
      end

      it 'should include applications associated with family1' do
        expect(assigns(:applications).map(&:id).map(&:to_s)).to include(application1.id.to_s)
      end

      it 'should NOT include applications associated with family2' do
        expect(assigns(:applications).map(&:id).map(&:to_s)).not_to include(application2.id.to_s)
      end
    end
  end

  context "copy an application" do
    let(:family1_id) { family.id }
    let!(:application) { FactoryBot.create :financial_assistance_application, :with_applicants, family_id: family.id, aasm_state: 'determined' }
    let(:current_hbx_profile) { OpenStruct.new(under_open_enrollment?: true) }

    before(:each) do
      sign_in user
      allow(HbxProfile).to receive(:current_hbx).and_return(current_hbx_profile)
      applicants = application.applicants
      application.add_or_update_relationships(applicants[0], applicants[1], 'spouse')
      application.add_or_update_relationships(applicants[0], applicants[2], 'parent')
      application.add_or_update_relationships(applicants[0], applicants[3], 'parent')
      application.add_or_update_relationships(applicants[1], applicants[2], 'parent')
      application.add_or_update_relationships(applicants[1], applicants[3], 'parent')
      application.add_or_update_relationships(applicants[2], applicants[3], 'sibling')
      application.relationships << ::FinancialAssistance::Relationship.new(kind: 'spouse', applicant_id: applicants[0].id, relative_id: applicants[1].id)
      application.relationships << ::FinancialAssistance::Relationship.new(kind: 'spouse', applicant_id: applicants[0].id, relative_id: applicants[1].id)
    end

    context 'when application service raises an error' do

      before do
        get :copy, params: { :id => application.id }
        @new_application = FinancialAssistance::Application.where(family_id: application.family_id, :id.ne => application.id).first
      end

      it "redirects to the new application copy" do
        expect(response).to redirect_to(edit_application_path(assigns(:application).reload))
      end

      it 'create duplicate application' do
        expect(@new_application.family_id).to eq application.family_id
      end

      it 'create duplicate application with assistance year' do
        expect(@new_application.assistance_year).not_to eq nil
      end

      it 'copies all the applicants' do
        expect(@new_application.applicants.count).to eq application.applicants.count
      end

      it 'does not copy duplicate relationships' do
        applicants = @new_application.applicants
        expect(@new_application.relationships.where(applicant_id: applicants[0].id, relative_id: applicants[1].id).count).to eq 1
      end

      it 'only copies relationships to the primary applicant' do
        applicants = @new_application.applicants
        expect(@new_application.relationships.where(applicant_id: applicants[2].id, relative_id: applicants[3].id).count).to eq 0
        expect(@new_application.relationships.count).to eq 6
      end
    end
  end

  describe 'GET #copy' do
    let(:primary_person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:new_family) { FactoryBot.create(:family, :with_primary_family_member, person: primary_person) }
    let(:application) { FactoryBot.create(:financial_assistance_application, family_id: new_family.id) }
    let(:hbx_profile) do
      FactoryBot.create(
        :hbx_profile,
        :normal_ivl_open_enrollment,
        us_state_abbreviation: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item,
        cms_id: "#{EnrollRegistry[:enroll_app].setting(:state_abbreviation).item.upcase}0"
      )
    end
    let(:ivl_product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, benefit_market_kind: :aca_individual) }

    let(:new_application) { FinancialAssistance::Application.where(family_id: new_family.id, :id.ne => application.id).first }

    before :each do
      primary_person.consumer_role.update_attributes!(identity_validation: 'valid')
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
        get :copy, params: { :id => application.id }
      end

      it 'returns success' do
        expect(response).to have_http_status(:redirect)
      end

      it 'creates a financial assistance application' do
        expect(new_application).to be_present
        expect(new_application.origin).to eq(:user)
        expect(new_application.generation_reason).to eq(:manual)
      end
    end

    context 'when the logged in user is Hbx Staff' do
      let(:hbx_person) { FactoryBot.create(:person) }
      let(:permission) { FactoryBot.create(:permission, :super_admin) }
      let(:hbx_staff) { FactoryBot.create(:hbx_staff_role, person: hbx_person, permission_id: permission.id) }
      let(:user) { FactoryBot.create(:user, person: hbx_staff.person) }

      before do
        get :copy, params: { :id => application.id }
      end

      it 'returns success' do
        expect(response).to have_http_status(:redirect)
      end

      it 'creates a financial assistance application' do
        expect(new_application).to be_present
        expect(new_application.origin).to eq(:admin)
        expect(new_application.generation_reason).to eq(:manual)
      end
    end

    context 'when the logged in user is an active broker' do
      let(:bap_id) { BSON::ObjectId.new }
      let(:broker_role) { FactoryBot.create(:broker_role, aasm_state: 'active', benefit_sponsors_broker_agency_profile_id: bap_id) }
      let(:user) { FactoryBot.create(:user, person: broker_role.person) }

      before do
        new_family.broker_agency_accounts.create!(
          is_active: true,
          writing_agent_id: broker_role.id,
          start_on: TimeKeeper.date_of_record,
          benefit_sponsors_broker_agency_profile_id: bap_id
        )
        allow(broker_role).to receive(:individual_market?).and_return(true)
        get :copy, params: { :id => application.id }
      end

      it 'returns success' do
        expect(response).to have_http_status(:redirect)
      end

      it 'creates a financial assistance application' do
        expect(new_application).to be_present
        expect(new_application.origin).to eq(:broker)
        expect(new_application.generation_reason).to eq(:manual)
      end
    end
  end
end

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

  describe '#index' do
    context 'primary person is RIDP verified' do
      it 'assigns applications' do
        get :index
        applications = FinancialAssistance::Application.where(family_id: family_id)
        expect(assigns(:applications)).to match_array(applications.to_a)
      end
    end

    context 'primary person is not RIDP verified' do
      it 'redirects to root_path with a flash message' do
        family.primary_person.consumer_role.update_attributes(identity_validation: 'na', application_validation: 'na')
        get :index
        expect(response).to redirect_to(main_app.root_path)
        expect(flash[:error]).to eq('Access not allowed for family_policy.index?, (Pundit policy)')
      end
    end
  end

  describe "GET edit" do
    context "With valid data" do
      it "should render" do
        get :edit, params: { id: application.id }
        expect(assigns(:application)).to eq application
        expect(response).to render_template(:financial_assistance_nav)
      end
    end

    context "when the request type is invalid" do
      it "should not render the raw_application template" do
        get :edit, params: { id: application.id }, format: :csv
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
        expect(response.media_type).to eq "text/csv"
      end

      it "should not render the raw_application template" do
        get :edit, params: { id: application.id }, format: :js
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
      end

      it "should not render the raw_application template" do
        get :edit, params: { id: application.id }, format: :xml
        expect(response.status).to eq 406
        expect(response.body).to eq "<error>Unsupported format</error>"
      end
    end

    context "With missing family id" do
      it "should find the correct application" do
        sign_in(admin_user)
        get :edit, params: { id: application.id }, session: { person_id: application.family.primary_person.id }
        expect(assigns(:application)).to eq application
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

      before { family.primary_person.consumer_role.move_identity_documents_to_verified }

      context 'hired by family' do
        before(:each) do
          family.broker_agency_accounts << BenefitSponsors::Accounts::BrokerAgencyAccount.new(benefit_sponsors_broker_agency_profile_id: broker_agency_profile.id,
                                                                                              writing_agent_id: writing_agent.id,
                                                                                              start_on: Time.now,
                                                                                              is_active: true)

          family.reload
        end

        it "should render" do
          get :edit, params: { id: application.id }, session: { person_id: family.primary_person.id }
          expect(assigns(:application)).to eq application
          expect(response).to render_template(:financial_assistance_nav)
        end
      end

      context 'not hired by family' do
        it "should render" do
          get :edit, params: { id: application.id }, session: { person_id: family.primary_person.id }
          expect(assigns(:application)).to eq application
          expect(response).to have_http_status(:redirect)
          expect(flash[:error]).to eq('Access not allowed for financial_assistance/application_policy.edit?, (Pundit policy)')
        end
      end
    end
  end

  context "POST save_preferences" do
    before do
      allow(controller).to receive(:haven_determination_is_enabled?).and_return(true)
      setup_faa_data
      allow(FinancialAssistance::Operations::Applications::MedicaidGateway::PublishApplication).to receive(:new).and_return(obj)
      allow(obj).to receive(:build_event).and_return(event)
      allow(event.success).to receive(:publish).and_return(true)
      controller.instance_variable_set(:@model, application.reload)
    end

    context "with applicants_attributes containing contact_method" do
      let(:params_with_contact_method) do
        {
          id: application.id,
          application: {
            applicants_attributes: {
              "0" => {
                id: applicant.id,
                contact_method: ["Mail", "Text"]
              }
            }
          }
        }
      end

      it "transforms contact_method properly when saving" do
        expect(controller).to receive(:transform_contact_methods!)
        post :save_preferences, params: params_with_contact_method
        expect(response).to redirect_to(submit_your_application_application_path(application))
      end

      it "transforms 'mail' and 'text' to 'paper and text message'" do
        post :save_preferences, params: params_with_contact_method
        expect(applicant.reload.contact_method).to eq("Paper and Text Message communications")
      end

      it "transforms only 'mail' to 'only paper'" do
        params = params_with_contact_method
        params[:application][:applicants_attributes]["0"][:contact_method] = ["Mail"]
        post :save_preferences, params: params
        expect(applicant.reload.contact_method).to eq("Only Paper communication")
      end

      it "transforms only 'Email' to 'electronic communication'" do
        params = params_with_contact_method
        params[:application][:applicants_attributes]["0"][:contact_method] = ["Email"]
        post :save_preferences, params: params
        expect(applicant.reload.contact_method).to eq("Only Electronic communications")
      end
    end

    context "when qhp_application feature is enabled" do
      before do
        allow(controller).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      it "redirects to review_and_submit path when successful" do
        post :save_preferences, params: { id: application.id, application: application_valid_params }
        expect(response).to redirect_to(review_and_submit_application_path(application))
      end
    end

    it "shows errors when @application does not save" do
      allow(application).to receive_message_chain('errors.full_messages').and_return(
        ["Hbx id can't be blank", "fake errors can't be blank"]
      )
      allow(FinancialAssistance::Application).to receive(:find_by).and_return(application)
      allow(application).to receive(:save).and_return(false)
      allow(application).to receive(:save!).with(validate: false).and_return(false)
      allow(application).to receive(:valid?).and_return(false)
      post :save_preferences, params: {application: application.attributes, id: application.id }
      expect(flash[:error]).to eq("Hbx id can't be blank, fake errors can't be blank")
    end

    it "shows errors when @model does not save and errors blank" do
      # to give errors
      allow(FinancialAssistance::Application).to receive(:find_by).and_return(application)
      allow(application).to receive(:save).and_return(false)
      allow(application).to receive(:save!).with(validate: false).and_return(false)
      allow(application).to receive(:valid?).and_return(false)
      post :save_preferences, params: {application: application.attributes, id: application.id }
      expect(flash[:error]).to eq("")
    end

    it "should render preferences if model is not saved" do
      post :save_preferences, params: { id: application.id }
      expect(response).to render_template 'preferences'
    end

    it "should redirect to the submit your application page if successful" do
      post :save_preferences, params: { id: application.id, application: application_valid_params }
      expect(response).to redirect_to(submit_your_application_application_path(application))
    end

    it "should set years_to_renew on application" do
      post :save_preferences, params: { id: application.id, application: application_valid_params.merge!("is_renewal_authorized" => "true") }
      application.reload
      expect(application.years_to_renew).to eq 5
    end
  end

  context "GET review_and_submit" do
    it 'should review and submit page' do
      application.update_attributes(:aasm_state => "draft")
      get :review_and_submit, params: { id: application.id }
      expect(assigns(:application)).to eq application
      expect(assigns(:application).aasm_state).to eq("draft")
      expect(response).to render_template(:financial_assistance_nav)
    end

    context "when the request type is invalid" do
      before do
        application.update_attributes(:aasm_state => "draft")
      end

      it "should not render the review_and_submit template" do
        get :review_and_submit, params: { id: application.id }, format: :csv
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
        expect(response.media_type).to eq "text/csv"
      end

      it "should not render the review_and_submit template" do
        get :review_and_submit, params: { id: application.id }, format: :js
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
      end

      it "should not render the review_and_submit template" do
        get :review_and_submit, params: { id: application.id }, format: :xml
        expect(response.status).to eq 406
        expect(response.body).to eq "<error>Unsupported format</error>"
      end
    end

    context 'when the application does not have valid relations' do
      before do
        allow_any_instance_of(FinancialAssistance::Application).to receive(:valid_relations?).and_return(false)
      end

      it 'should throw and redirect to relationship page' do
        application.update_attributes(:aasm_state => "draft")
        get :review_and_submit, params: { id: application.id }
        expect(response).to redirect_to(application_relationships_path(application))
      end
    end
  end

  context "GET review" do
    before do
      sign_in(user)
    end

    it "should be successful" do
      application.update_attributes(:aasm_state => "submitted")
      get :review, params: { id: application.id }
      expect(assigns(:application)).to eq application
    end

    it 'raises an error if application cannot be found' do
      input_params = { id: FinancialAssistance::Application.new.id }
      expect do
        get :review, params: input_params
      end.to raise_error(
        Mongoid::Errors::DocumentNotFound,
        /#{input_params[:id]}/
      )
    end

    context "when the request type is invalid" do
      before do
        application.update_attributes(:aasm_state => "submitted")
      end

      it "should not render the review template" do
        get :review, params: { id: application.id }, format: :csv
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
        expect(response.media_type).to eq "text/csv"
      end

      it "should not render the review template" do
        get :review, params: { id: application.id }, format: :js
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
      end

      it "should not render the review template" do
        get :review, params: { id: application.id }, format: :xml
        expect(response.status).to eq 406
        expect(response.body).to eq "<error>Unsupported format</error>"
      end
    end
  end

  context "GET raw" do
    let(:temp_file) do
      [{"demographics" => {} },
       {"financial_assistance_info" => {"TAX INFO" => nil,
                                        "INCOME" => nil,
                                        "INCOME ADJUSTMENTS" => nil,
                                        "HEALTH COVERAGE" => nil,
                                        "OTHER QUESTIONS" => nil}}]
    end

    before do
      allow(File).to receive(:read).with("./components/financial_assistance/app/views/financial_assistance/applications/raw_application_hra.yml.erb").and_return("")
      allow(File).to receive(:read).with("./components/financial_assistance/app/views/financial_assistance/applications/raw_application.yml.erb").and_return("")
      allow(YAML).to receive(:safe_load).with("").and_return(temp_file)
      user.update_attributes(roles: ["hbx_staff"])
    end

    it "should be successful" do
      application.update_attributes(:aasm_state => "submitted")
      get :raw_application, params: { id: application.id }
      expect(assigns(:application)).to eq application
    end

    it "should redirect to applications page for draft application" do
      get :raw_application, params: { id: application.id }
      expect(response).to redirect_to(applications_path)
    end

    it "should not redirect to applications page for draft application if qhp application feature is enabled" do
      allow(controller).to receive(:qhp_application_feature_enabled?).and_return(true)
      get :raw_application, params: { id: application.id }
      expect(response).to render_template(:raw_application)
    end

    it 'raises an error if application cannot be found' do
      input_params = { id: FinancialAssistance::Application.new.id }
      expect do
        get :raw_application, params: input_params
      end.to raise_error(
        Mongoid::Errors::DocumentNotFound,
        /#{input_params[:id]}/
      )
    end

    it 'raises an error if application cannot be found' do
      user.update_attributes(roles: ["comsumer_role"])

      input_params = { id: FinancialAssistance::Application.new.id }
      expect do
        get :raw_application, params: input_params
      end.to raise_error(
        Mongoid::Errors::DocumentNotFound,
        /#{input_params[:id]}/
      )
    end

    context "generate income hash" do
      it "should include unemployment income if feature enabled" do
        skip "skipped: unemployment income feature not enabled" unless FinancialAssistanceRegistry[:unemployment_income].enabled?

        application.update_attributes(:aasm_state => "submitted")
        get :raw_application, params: { id: application.id }
        # Translations are not resolved here. Only checking for presence of income keys.
        expect(assigns(:income_coverage_hash)[applicant.id]["INCOME"].present?).to eq true
      end
    end

    context "when the request type is invalid" do
      before do
        application.update_attributes(:aasm_state => "submitted")
      end

      it "should not render the raw_application template" do
        get :raw_application, params: { id: application.id }, format: :csv
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
        expect(response.media_type).to eq "text/csv"
      end

      it "should not render the raw_application template" do
        get :raw_application, params: { id: application.id }, format: :js
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
      end

      it "should not render the raw_application template" do
        get :raw_application, params: { id: application.id }, format: :xml
        expect(response.status).to eq 406
        expect(response.body).to eq "<error>Unsupported format</error>"
      end
    end
  end

  describe "PATCH update_application_year" do
    context "with different assistance_year" do
      before do
        patch :update_application_year, params: { id: application.id, application: {assistance_year: TimeKeeper.date_of_record.year + 1} }
      end
      it "should update the assistance_year" do
        expect(application.reload.assistance_year).to eq TimeKeeper.date_of_record.year + 1
      end
    end
  end

  describe  "GET wait_for_eligibility_response" do
    context "With valid data" do
      it "should redirect to eligibility_response_error if doesn't find the ED on wait_for_eligibility_response page" do
        get :wait_for_eligibility_response, params: { id: application.id }
        expect(assigns(:application)).to eq application
      end
    end

    context "when the request type is invalid" do
      before do
        application.update_attributes(:aasm_state => "submitted")
      end

      it "should not render the wait_for_eligibility_response template" do
        get :wait_for_eligibility_response, params: { id: application.id }, format: :csv
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
        expect(response.media_type).to eq "text/csv"
      end

      it "should not render the wait_for_eligibility_response template" do
        get :wait_for_eligibility_response, params: { id: application.id }, format: :js
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
      end

      it "should not render the wait_for_eligibility_response template" do
        get :wait_for_eligibility_response, params: { id: application.id }, format: :xml
        expect(response.status).to eq 406
        expect(response.body).to eq "<error>Unsupported format</error>"
      end
    end

    context "With missing family id" do
      it "should find application" do
        sign_in(admin_user)
        get :wait_for_eligibility_response, params: { id: application.id }, session: { person_id: application.family.primary_person.id }
        expect(assigns(:application)).to eq application
      end
    end
  end

  describe "GET eligibility_results" do
    context "With valid data" do
      it 'should get eligibility results' do
        get :eligibility_results, params: {:id => application.id, :cur => 1}
        expect(assigns(:application)).to eq application
        expect(response).to render_template(:financial_assistance_nav)
      end
    end

    context "With missing family id" do
      it 'should find the correct application' do
        sign_in(admin_user)
        get :eligibility_results, params: {:id => application.id, :cur => 1}, session: { person_id: application.family.primary_person.id }
        expect(assigns(:application)).to eq application
      end
    end
  end

  describe "GET application_publish_error" do
    context "With valid data" do

      it 'should get application publish error' do
        get :application_publish_error, params: { id: application.id }
        expect(assigns(:application)).to eq application
        expect(response).to render_template(:financial_assistance_nav)
      end
    end

    context "With missing family id" do
      let!(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
      let!(:admin_user) {FactoryBot.create(:user, :with_hbx_staff_role, :person => admin_person)}
      let!(:permission) { FactoryBot.create(:permission, :super_admin) }
      let!(:update_admin) { admin_person.hbx_staff_role.update_attributes(permission_id: permission.id) }

      it 'should find application with missing family id' do
        family.primary_person.consumer_role.move_identity_documents_to_verified
        sign_in(admin_user)
        get :application_publish_error, params: { id: application.id }, session: { person_id: family.primary_person.id }
        expect(assigns(:application)).to eq application
        expect(response).to render_template(:financial_assistance_nav)
      end
    end
  end

  describe "GET check eligibility results received" do
    context "doesn't have the success status code" do

      it "should return false" do
        get :check_eligibility_results_received, params: { id: application.id }
        expect(response.body).to eq "false"
      end
    end

    context 'with success status code and determined application' do

      let(:cache_key) { "application_#{application.hbx_id}_determined" }
      let(:set_rails_cache) { Rails.cache.write(cache_key, Time.now.strftime('%Y-%m-%d %H:%M:%S.%L'), expires_in: 5.minutes) }

      before do
        application.update_attributes(determination_http_status_code: 200, aasm_state: 'determined')
        set_rails_cache
        get :check_eligibility_results_received, params: { id: application.id }
      end

      after do
        Rails.cache.delete(cache_key)
      end

      it 'should return true for response body' do
        expect(response.body).to eq 'true'
      end

      it 'should return true for response mime type' do
        expect(response.media_type).to eq('text/plain')
      end
    end
  end

  context "with missing family id" do
    it "should find the correct application" do
      sign_in(admin_user)
      get :check_eligibility_results_received, params: { id: application.id }, session: { person_id: application.family.primary_person.id }
      expect(assigns(:application)).to eq application
    end
  end


  describe 'GET eligibility_response_error' do
    context 'where application did not receive eligibility determination' do
      before do
        get :eligibility_response_error, params: { id: application.id }
      end

      it 'should assign application to instance variable' do
        expect(assigns(:application)).to eq application
      end

      it "should update application's determination_http_status_code to 999" do
        expect(application.reload.determination_http_status_code).to eq(999)
      end

      it 'should render template eligibility_response_error' do
        expect(response).to render_template("eligibility_response_error")
      end
    end

    context "when the request type is invalid" do
      before do
        application.update_attributes(:aasm_state => "submitted")
      end

      it "should not render the eligibility_response_error template" do
        get :eligibility_response_error, params: { id: application.id }, format: :csv
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
        expect(response.media_type).to eq "text/csv"
      end

      it "should not render the eligibility_response_error template" do
        get :eligibility_response_error, params: { id: application.id }, format: :js
        expect(response.status).to eq 406
        expect(response.body).to eq "Unsupported format"
      end

      it "should not render the eligibility_response_error template" do
        get :eligibility_response_error, params: { id: application.id }, format: :xml
        expect(response.status).to eq 406
        expect(response.body).to eq "<error>Unsupported format</error>"
      end
    end

    context 'where application received eligibility determination' do
      before do
        application.update_attributes!(determination_http_status_code: 200, aasm_state: 'determined')
        get :eligibility_response_error, params: { id: application.id }
      end

      it 'should assign application to instance variable' do
        expect(assigns(:application)).to eq application
      end

      it 'should redirect to eligibility_results if application status is 200/203 and application is in determined state' do
        expect(response).to redirect_to(eligibility_results_application_path(application.id, cur: 1))
      end
    end

    context "with missing family id" do
      it "finds the correct application" do
        sign_in(admin_user)
        get :eligibility_response_error, params: { id: application.id }, session: { person_id: application.family.primary_person.id }
        expect(assigns(:application)).to eq application
      end
    end
  end
end

RSpec.describe FinancialAssistance::ApplicationsController, dbclean: :after_each, type: :controller do
  include Dry::Monads[:do, :result]

  before :all do
    DatabaseCleaner.clean
  end

  context "with :filtered_application_list on" do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, first_name: "test1") }
    let(:user) { FactoryBot.create(:user, :person => person) }

    before do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:filtered_application_list).and_return(true)
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:haven_determination).and_call_original
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:medicaid_gateway_determination).and_call_original
      Rails.application.reload_routes!
    end

    after do
      allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:filtered_application_list).and_call_original
      Rails.application.reload_routes!
    end

    describe 'Feature flagged endpoints', type: :request do

      describe "GET /applications" do
        let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
        let!(:application) { FactoryBot.create :financial_assistance_application, :with_applicants, family_id: family.id, aasm_state: 'determined' }

        before(:each) do
          person.consumer_role.move_identity_documents_to_verified
          sign_in(user)
        end

        it 'succeeds' do
          get '/financial_assistance/applications'
          expect(response).to render_template(:index_with_filter)
        end

        context "when the request type is invalid" do
          let(:operation_instance) { instance_double(FinancialAssistance::Operations::Applications::QueryFilteredApplications) }
          let(:failure_result) { Dry::Monads::Result::Failure.new({message: "error message"}) }

          it "should not render the index_with_filter template" do
            allow(FinancialAssistance::Operations::Applications::QueryFilteredApplications).to receive(:new).and_return(operation_instance)
            allow(operation_instance).to receive(:call).and_return(failure_result)
            get '/financial_assistance/applications', params: { format: :csv }
            expect(response.status).to eq 406
            expect(response.body).to eq "Unsupported format"
            expect(response.media_type).to eq "text/csv"
          end

          it "should not render the index_with_filter template" do
            get '/financial_assistance/applications', params: { format: :fake }
            expect(response.status).to eq 406
            expect(response.body).to eq "Unsupported format"
          end

          it "should not render the index_with_filter template" do
            get '/financial_assistance/applications', params: { format: :xml }
            expect(response.status).to eq 406
            expect(response.body).to eq "<error>Unsupported format</error>"
          end
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
