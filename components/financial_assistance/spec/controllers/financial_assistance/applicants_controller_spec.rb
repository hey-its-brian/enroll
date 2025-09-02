# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::ApplicantsController, dbclean: :after_each, type: :controller do
  routes { FinancialAssistance::Engine.routes }
  let!(:user) { FactoryBot.create(:user, :person => person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, dob: TimeKeeper.date_of_record - 40.years)}
  let(:family_id) { BSON::ObjectId.new }
  let(:family_member_id) { BSON::ObjectId.new }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, id: family_id, person: person) }
  let!(:hbx_profile) { FactoryBot.create(:hbx_profile,:open_enrollment_coverage_period) }
  let!(:application) { FactoryBot.create(:application, family_id: family_id, aasm_state: "draft",effective_date: TimeKeeper.date_of_record) }
  let!(:applicant) do
    FactoryBot.create(:applicant, application: application, dob: TimeKeeper.date_of_record - 40.years, is_primary_applicant: true, is_claimed_as_tax_dependent: false, is_self_attested_blind: false, has_daily_living_help: false,
                                  need_help_paying_bills: false, family_member_id: family_member_id)
  end
  let(:financial_assistance_applicant_valid) do
    {
      "is_ssn_applied" => "false",
      "non_ssn_apply_reason" => "we",
      "is_pregnant" => "false",
      "pregnancy_due_on" => "",
      "children_expected_count" => "",
      "is_post_partum_period" => "false",
      "pregnancy_end_on" => "09/21/2017",
      "is_former_foster_care" => "false",
      "foster_care_us_state" => "",
      "age_left_foster_care" => "",
      "is_student" => "false",
      "student_kind" => "",
      "student_status_end_on" => "",
      "student_school_kind" => "",
      "is_self_attested_blind" => "false",
      "has_daily_living_help" => "false",
      "need_help_paying_bills" => "false"
    }.tap do |params_hash|
      params_hash['is_primary_caregiver'] = "false" if FinancialAssistanceRegistry.feature_enabled?(:primary_caregiver_other_question)
    end
  end
  let(:financial_assistance_applicant_invalid) do
    {
      "is_required_to_file_taxes" => nil,
      "is_claimed_as_tax_dependent" => nil
    }
  end

  let(:applicant_params) do
    {
      "is_required_to_file_taxes" => true,
      "is_claimed_as_tax_dependent" => false,
      "has_job_income" => "false",
      "has_self_employment_income" => "false",
      "has_other_income" => "false",
      "has_deductions" => "false",
      "has_enrolled_health_coverage" => "false",
      "has_eligible_health_coverage" => "false"
    }.tap do |params_hash|
      params_hash['is_primary_caregiver'] = "false" if FinancialAssistanceRegistry.feature_enabled?(:primary_caregiver_other_question)
    end
  end

  before do
    # Tests to make sure it can handle admin user
    allow(user).to receive(:has_hbx_staff_role?).and_return(true)
    person.consumer_role.move_identity_documents_to_verified
    sign_in(user)
  end

  context "GET index" do
    before do
      allow_any_instance_of(FinancialAssistance::ApplicantsController).to receive(:authorize).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    end

    it "should assign the application" do
      get :index, params: { application_id: application.id }
      expect(assigns(:application)).to eq application
    end

    it "should render the index template" do
      get :index, params: { application_id: application.id }
      expect(response).to render_template(:index)
    end

    context "when using bs4_consumer_flow" do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(true)
      end

      it "should use the financial_assistance_progress layout" do
        get :index, params: { application_id: application.id }
        expect(response).to render_template(layout: "layouts/financial_assistance_progress")
      end
    end

    context "when not using bs4_consumer_flow" do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(false)
      end

      it "should use the financial_assistance_nav layout" do
        get :index, params: { application_id: application.id }
        expect(response).to render_template(layout: "layouts/financial_assistance_nav")
      end
    end
  end

  context "GET show" do
    before do
      allow_any_instance_of(FinancialAssistance::ApplicantsController).to receive(:authorize).and_return(true)
      allow(controller).to receive(:set_summary_helpers).and_return(true)
    end

    it "should assign the application" do
      get :show, params: { application_id: application.id, id: applicant.id  }
      expect(assigns(:application)).to eq application
    end

    it "should render the index template" do
      get :show, params: { application_id: application.id, id: applicant.id  }
      expect(response).to render_template(:show)
    end

    context "when using bs4_consumer_flow" do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(true)
      end

      it "should use the financial_assistance_progress layout" do
        get :show, params: { application_id: application.id, id: applicant.id  }
        expect(response).to render_template(layout: "layouts/financial_assistance_progress")
      end
    end

    context "when not using bs4_consumer_flow" do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(false)
      end

      it "should use the financial_assistance_nav layout" do
        get :show, params: { application_id: application.id, id: applicant.id  }
        expect(response).to render_template(layout: "layouts/financial_assistance_nav")
      end
    end

    context 'pundit authorization' do
      context 'when invalid application id is provided' do
        it 'should raise Pundit::NotAuthorizedError' do
          get :show, params: { application_id: BSON::ObjectId.new, id: applicant.id }
          expect(flash[:error]).to eq('Access not allowed for financial_assistance/applicant.show?, (Pundit policy)')
        end
      end

      context 'when invalid applicant id is provided' do
        it 'should raise Pundit::NotAuthorizedError' do
          get :show, params: { application_id: BSON::ObjectId.new, id: applicant.id }
          expect(flash[:error]).to eq('Access not allowed for financial_assistance/applicant.show?, (Pundit policy)')
        end
      end

      context 'when valid application id applicant id is provided' do
        it 'should not raise Pundit::NotAuthorizedError' do
          get :show, params: { application_id: application.id, id: applicant.id }
          expect(flash[:error]).to eq nil
        end
      end
    end
  end

  context "GET other questions" do
    it "should assign applications", dbclean: :after_each do
      get :other_questions, params: { application_id: application.id, id: applicant.id }
      expect(assigns(:applicant).id).to eq applicant.id
      expect(response).to render_template(:financial_assistance_nav)
    end

    it "should not assign applications", dbclean: :after_each do
      get :other_questions, params: { application_id: application.id, id: applicant.id }, format: :js
      expect(response).not_to render_template(:financial_assistance_nav)
    end
  end

  context "GET tax_info" do
    it "should not render tax_info if request is not html" do
      get :tax_info, params: { application_id: application.id, id: applicant.id }, format: :js
      expect(response).not_to render_template 'financial_assistance_nav'
    end

    it "should render if it is html", dbclean: :after_each do
      get :tax_info, params: { application_id: application.id, id: applicant.id }
      expect(assigns(:applicant).id).to eq applicant.id
      expect(response).to render_template(:financial_assistance_nav)
    end
  end

  context "GET applicant_is_eligible_for_joint_filing" do
    let(:dependent1) { FactoryBot.create(:person) }
    let(:family_member_dependent) { FactoryBot.build(:family_member, person: dependent1, family: family)}
    let!(:applicant2) do
      FactoryBot.create(:applicant,
                        first_name: "James", last_name: "Bond", gender: "male", dob: Date.new(1993, 3, 8),
                        person_hbx_id: dependent1.hbx_id,
                        application: application,
                        family_member_id: family_member_dependent.id)
    end


    before do
      applicant1 = application.applicants.first
      applicant2 = application.applicants.last
      application.add_or_update_relationships(applicant1, applicant2, "spouse")
    end

    it "should render plain text" do
      get :applicant_is_eligible_for_joint_filing, params: {"application_id" => application.id, "applicant_id" => applicant2.id}, format: :text
      expect(response.status).to be 200
      expect(response.content_type).to eq("text/plain; charset=utf-8")
    end

    it "should render plain text" do
      get :applicant_is_eligible_for_joint_filing, params: {"application_id" => application.id, "applicant_id" => applicant2.id}, format: :js
      expect(response.status).to be 406
    end
  end

  context "POST save_tax_info" do
    let(:family_member_id2) { BSON::ObjectId.new }
    let!(:applicant2) do
      FactoryBot.create(:applicant,
                        application: application,
                        dob: TimeKeeper.date_of_record - 40.years,
                        is_primary_applicant: false,
                        is_required_to_file_taxes: nil,
                        is_claimed_as_tax_dependent: nil,
                        is_self_attested_blind: false,
                        has_daily_living_help: false,
                        need_help_paying_bills: false,
                        family_member_id: family_member_id2)
    end
    it "should not render tax_info if request is not html" do
      post :save_tax_info, params: { application_id: application.id, id: applicant.id }, format: :js
      expect(response).not_to render_template 'financial_assistance_nav'
    end

    it "should not redirect to job income page when not passing correct params" do
      post :save_tax_info, params: { application_id: application.id, id: applicant2.id, applicant: {claimed_as_tax_dependent_by: nil, is_claimed_as_tax_dependent: true} }
      expect(response.status).to eq 302
      expect(response.headers['Location']).not_to have_content 'incomes'
      expect(response.headers['Location']).to have_content 'tax_info'
    end

    it "should save tax info and redirect to job income page with valid params", dbclean: :after_each do
      post :save_tax_info, params: { application_id: application.id, id: applicant2.id, applicant: applicant_params }
      expect(response.status).to eq 302
      expect(response).to redirect_to(application_applicant_incomes_path(application, applicant2))
    end
  end

  context "GET save questions" do
    before do
      applicant.update_attributes(is_primary_caregiver: nil) if FinancialAssistanceRegistry.feature_enabled?(:primary_caregiver_other_question)
    end
    it "should save questions and redirects to edit_financial_assistance_application_path", dbclean: :after_each do
      get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: financial_assistance_applicant_valid }
      expect(response).to have_http_status(302)
      expect(response.headers['Location']).to have_content 'edit'
      expect(response).to redirect_to(edit_application_path(application))
      if FinancialAssistanceRegistry.feature_enabled?(:primary_caregiver_other_question)
        applicant.reload
        expect(applicant.is_primary_caregiver.nil?).to eq(false)
      end
    end
    # TODO: This is run under the save context of :other_qns which runs the method presence_of_attr_other_qns and does not validate the is_required_to_file_taxes or
    # is_claimed_as_tax_dependent, which are passed as nil here as "invalid params."
    # Should they be added to the presence_of_attr_other_qns method?
    it "should not save and redirects to other_questions_financial_assistance_application_applicant_path", dbclean: :after_each do
      get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: financial_assistance_applicant_invalid }
      expect(response).to have_http_status(302)
      expect(response.headers['Location']).to have_content 'other_questions'
      expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
    end

    context "Pregnancy questions validation" do
      let(:faa_invalid_params_pregenancy) do
        {
          "is_pregnant" => true,
          "pregnancy_due_on" => nil,
          "children_expected_count" => nil
        }
      end

      let(:faa_without_due_date) do
        {
          "is_pregnant" => true,
          "pregnancy_due_on" => nil,
          "children_expected_count" => 1
        }
      end

      let(:faa_expected_count_nil) do
        {
          "is_pregnant" => true,
          "pregnancy_due_on" => (TimeKeeper.date_of_record + 1).strftime("%m/%d/%Y"),
          "children_expected_count" => nil
        }
      end

      let(:faa_valid_params_pregnancy) do
        {
          "is_pregnant" => true,
          "pregnancy_due_on" => (TimeKeeper.date_of_record + 1).strftime("%m/%d/%Y"),
          "children_expected_count" => 1
        }
      end

      let(:faa_invalid_past_due_date) do
        {
          "is_pregnant" => true,
          "pregnancy_due_on" => (TimeKeeper.date_of_record - 1).strftime("%m/%d/%Y"),
          "children_expected_count" => 1
        }
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with invalid params", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_invalid_params_pregenancy }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with due date nill", dbclean: :after_each do
        allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:primary_caregiver_other_question).and_return(true)
        allow(FinancialAssistanceRegistry).to receive(:feature_enabled?).with(:pregnancy_due_on_required).and_return(true)
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_without_due_date }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with children_expected_count nill", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_expected_count_nil }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should save and redirects to edit_financial_assistance_application_path with valid pregnancy responses", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_valid_params_pregnancy }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'edit'
        expect(response).to redirect_to(edit_application_path(application))
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with invalid past due date", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_invalid_past_due_date }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end
    end

    context "is_post_partum_period" do
      let(:faa_invalid_post_partum_period_params) do
        {
          "is_post_partum_period" => true,
          "is_enrolled_on_medicaid" => nil,
          "pregnancy_end_on" => nil
        }
      end

      let(:faa_without_preg_end_date) do
        {
          "is_post_partum_period" => true,
          "pregnancy_end_on" => nil,
          "is_enrolled_on_medicaid" => true
        }
      end

      let(:faa_enrolled_on_medicaid_nil) do
        {
          "is_post_partum_period" => true,
          "pregnancy_end_on" => (applicant.dob + 20.years).strftime("%m/%d/%Y"),
          "is_enrolled_on_medicaid" => nil
        }
      end

      let(:faa_valid_params_partum_period_params) do
        {
          "is_post_partum_period" => true,
          "pregnancy_end_on" => (applicant.dob + 20.years).strftime("%m/%d/%Y"),
          "is_enrolled_on_medicaid" => true
        }
      end

      let(:partum_period_params_with_out_enrolled_on_medicaid_params) do
        {
          "is_pregnant" => "false",
          "pregnancy_due_on" => "",
          "children_expected_count" => "",
          "is_post_partum_period" => "true",
          "pregnancy_end_on" => (TimeKeeper.date_of_record - 1.month).strftime("%m/%d/%Y")
        }
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with invalid params", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_invalid_post_partum_period_params }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with end date nil", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_without_preg_end_date }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should save and redirects to redirects to edit_financial_assistance_application_path with enrolled_on_medicaid nil", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_enrolled_on_medicaid_nil }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'edit'
        expect(response).to redirect_to(edit_application_path(application))
      end

      it "should save and redirects to redirects to edit_financial_assistance_application_path with valid params", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: faa_valid_params_partum_period_params }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'edit'
        expect(response).to redirect_to(edit_application_path(application))
      end

      context "when applicant not applying for coverage and in post_partum_period" do
        it "should not return Was This Person On Medicaid During Pregnancy?' Should Be Answered error" do
          applicant.update_attributes(is_enrolled_on_medicaid: nil, is_applying_coverage: false)
          get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: partum_period_params_with_out_enrolled_on_medicaid_params }
          expect(response).to have_http_status(302)
          expect(response.headers['Location']).to have_content 'edit'
          expect(response).to redirect_to(edit_application_path(application))
        end
      end
    end

    context "age_of_applicant" do
      let(:is_invalid_former_foster_care) do
        {
          "is_former_foster_care" => true,
          "foster_care_us_state" => nil,
          "age_left_foster_care" => nil
        }
      end

      let(:is_invalid_former_foster_care1) do
        {
          "is_former_foster_care" => true,
          "foster_care_us_state" => "DC",
          "age_left_foster_care" => nil
        }
      end

      let(:is_valid_former_foster_care) do
        {
          "is_former_foster_care" => true,
          "foster_care_us_state" => "DC",
          "age_left_foster_care" => 1
        }.tap do |params_hash|
          params_hash['is_primary_caregiver'] = "false" if FinancialAssistanceRegistry.feature_enabled?(:primary_caregiver_other_question)
        end
      end

      before :each do
        applicant.update_attributes(is_applying_coverage: true,
                                    dob: TimeKeeper.date_of_record - 20.years,
                                    is_post_partum_period: true,
                                    pregnancy_end_on: applicant.dob + 20.years,
                                    is_enrolled_on_medicaid: true)
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with invalid params", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: {} }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with foster_care_us_state nill", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: is_invalid_former_foster_care }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should not save and redirects to other_questions_financial_assistance_application_applicant_path with age_left_foster_care nill", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: is_invalid_former_foster_care1 }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'other_questions'
        expect(response).to redirect_to(other_questions_application_applicant_path(application, applicant))
      end

      it "should save and redirects to edit_financial_assistance_application_path with valid params", dbclean: :after_each do
        get :save_questions, params: { application_id: application.id, id: applicant.id, applicant: is_valid_former_foster_care }
        expect(response).to have_http_status(302)
        expect(response.headers['Location']).to have_content 'edit'
        expect(response).to redirect_to(edit_application_path(application))
      end
    end
  end

  context "PATCH update" do
    let(:family_member_id2) { BSON::ObjectId.new }
    let!(:applicant2) do
      FactoryBot.create(:applicant,
                        application: application,
                        dob: TimeKeeper.date_of_record - 40.years,
                        is_primary_applicant: false,
                        is_claimed_as_tax_dependent: false,
                        is_self_attested_blind: false,
                        has_daily_living_help: false,
                        need_help_paying_bills: false,
                        family_member_id: family_member_id2)
    end

    let(:update_params) do
      {
        application_id: application.id,
        id: applicant.id,
        applicant: {
          is_applying_coverage: false,
          :is_homeless => '0',
          :is_temporarily_out_of_state => '0',
          relationship: nil,
          first_name: 'update',
          last_name: 'updated',
          gender: 'male',
          dob: (TimeKeeper.date_of_record - 20.years).strftime("%Y-%m-%d"),
          ssn: nil,
          addresses_attributes: {'0': {kind: 'home', city: 'Bar Harbor', county: 'Cumberland', state: 'ME', zip: '04401', address_1: '1600 Main St'}},
          is_consumer_role: false
        }
      }
    end

    before do
      applicant.update_attributes!(is_applying_coverage: true)
      applicant2.update_attributes!(is_applying_coverage: true)
    end

    context "primary applicant updating information" do
      it "should update primary's information when relationship param is blank" do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(false)
        patch :update, params: update_params
        applicant.reload
        expect(applicant.is_applying_coverage).to eq false
        expect(applicant.first_name).to eq 'update'
      end
    end

    context "dependent applicant updating information" do
      it "should not update applicant's information when relationship param is blank" do
        update_params[:id] = applicant2.id
        patch :update, params: update_params
        applicant.reload
        expect(applicant.is_applying_coverage).to eq true
      end
    end

    context "applicant's addresses are successfully updated" do

      let(:county_params) {  update_params[:applicant][:addresses_attributes][:'0'][:county]}

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:counties_import).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_update_family_save).and_return(true)
      end

      it "should update applicant's address" do
        patch :update, params: update_params
        applicant.reload
        expect(applicant.addresses.first.county).to eql(county_params)
      end
    end

    context "applicant's address attributes are nil" do

      let(:blank_address_params) do
        {
          application_id: application.id,
          id: applicant.id,
          applicant: {
            is_applying_coverage: false,
            :is_homeless => '0',
            :is_temporarily_out_of_state => '0',
            relationship: nil,
            first_name: 'update',
            last_name: 'updated',
            gender: 'male',
            dob: (TimeKeeper.date_of_record - 20.years).strftime("%Y-%m-%d"),
            ssn: nil,
            addresses_attributes: {'0': {kind: '', city: '', county: '', state: '', zip: '', address_1: ''}},
            is_consumer_role: false
          }
        }
      end

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:counties_import).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_update_family_save).and_return(true)
      end

      it "should handle nil address attributes" do
        patch :update, params: blank_address_params
        applicant.reload
        expect(applicant.addresses).to eql([])
      end
    end

    context "applicant's address attributes do not contain county" do

      let(:non_county_params) do
        {
          application_id: application.id,
          id: applicant.id,
          applicant: {
            is_applying_coverage: false,
            :is_homeless => '0',
            :is_temporarily_out_of_state => '0',
            relationship: nil,
            first_name: 'update',
            last_name: 'updated',
            gender: 'male',
            dob: (TimeKeeper.date_of_record - 20.years).strftime("%Y-%m-%d"),
            ssn: nil,
            addresses_attributes: {'0': {kind: 'home', city: 'Washington', state: 'DC', zip: '20003', address_1: '1600 Main St'}},
            is_consumer_role: false
          }
        }
      end

      it "should not include county" do
        patch :update, params: non_county_params
        applicant.reload
        expect(applicant.addresses.first.county).to be_blank
      end
    end

    context "dependent's address is updated" do

      let(:dependent) { application.applicants.last }

      let(:dependent_params) do
        {
          application_id: application.id,
          id: applicant.id,
          applicant: {
            is_applying_coverage: false,
            :is_homeless => '0',
            :is_temporarily_out_of_state => '0',
            relationship: 'spouse',
            first_name: 'update',
            last_name: 'updated',
            gender: 'male',
            dob: (TimeKeeper.date_of_record - 20.years).strftime("%Y-%m-%d"),
            ssn: nil,
            addresses_attributes: {'0': {kind: 'home', city: 'Bar Harbor', county: 'Cumberland', state: 'ME', zip: '04401', address_1: '1600 Main St'}},
            is_consumer_role: false
          }
        }
      end

      before do
        allow(dependent).to receive(:relation_with_primary).and_return('spouse')
        dependent_params[:id] = dependent.id
        dependent.update_attributes!(relationship: 'spouse')
        dependent.update_attributes!(same_with_primary: true)
        allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:counties_import).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_update_family_save).and_return(true)
      end

      it "should handle dependent's addresses" do
        patch :update, params: dependent_params
        application.reload
        dependent.reload
        expect(dependent.addresses.first.county).to eql('Cumberland')
      end
    end

    context "dependent's address" do
      let(:primary_applicant) { application.applicants.first }
      let(:dependent) { application.applicants.last }

      let(:dependent_params) do
        {
          application_id: application.id,
          id: applicant.id,
          is_dependent: "true"
        }
      end

      let(:applicant_params) do
        {
          same_with_primary: "true",
          is_applying_coverage: false,
          :is_homeless => '0',
          :is_temporarily_out_of_state => '0',
          relationship: 'spouse',
          first_name: 'update',
          last_name: 'updated',
          gender: 'male',
          dob: (TimeKeeper.date_of_record - 20.years).strftime("%Y-%m-%d"),
          ssn: nil,
          addresses_attributes: {'0': {kind: 'home', city: '', county: '', state: '', zip: '', address_1: ''}},
          is_consumer_role: false
        }
      end

      before do
        allow(dependent).to receive(:relation_with_primary).and_return('spouse')
        primary_applicant.addresses << FinancialAssistance::Locations::Address.new({kind: 'home', city: 'Bar Harbor', county: 'Cumberland', state: 'ME', zip: '04401', address_1: '1600 Main St'})
        dependent_params[:id] = dependent.id
        dependent.update_attributes!(relationship: 'spouse')
        dependent.update_attributes!(same_with_primary: true)
        allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:counties_import).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:financial_assistance).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_update_family_save).and_return(true)
      end

      context "when same_with_primary is true" do
        it "should update dependent's addresses with primary" do
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(same_with_primary: "true"))
          application.reload
          dependent.reload
          expect(dependent.addresses.first.county).to eql('Cumberland')
        end
      end

      context "when same_with_primary is false" do
        it "should not update dependent's addresses with primary" do
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(same_with_primary: "false"))
          application.reload
          dependent.reload
          expect(dependent.addresses.first).to be_nil
        end
      end
    end

    context "dependent's indian tribe member" do
      let(:dependent) { application.applicants.last }

      let(:dependent_params) do
        {
          application_id: application.id,
          id: dependent.id,
          is_dependent: "true"
        }
      end

      let(:applicant_params) do
        {
          same_with_primary: "true",
          is_applying_coverage: is_applying_coverage,
          :is_homeless => '0',
          :is_temporarily_out_of_state => '0',
          relationship: 'spouse',
          first_name: 'update',
          last_name: 'updated',
          gender: 'male',
          dob: (TimeKeeper.date_of_record - 20.years).strftime("%Y-%m-%d"),
          ssn: nil,
          addresses_attributes: {'0': {kind: 'home', city: '', county: '', state: '', zip: '', address_1: ''}},
          is_consumer_role: false,
          indian_tribe_member: true,
          tribal_state: 'DC',
          tribal_name: 'Cherokee',
          tribe_codes: ['123'],
          us_citizen: us_citizen,
          naturalized_citizen: false,
          eligible_immigration_status: true,
          is_incarcerated: false
        }
      end

      before do
        allow(EnrollRegistry[:indian_alaskan_tribe_details].feature).to receive(:is_enabled).and_return(true)
      end

      context "when dependent without us_citizen is applying for coverage" do
        let!(:is_applying_coverage) { true }
        let(:us_citizen) { true }

        it "should update tribe details " do
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(same_with_primary: "true"))
          application.reload
          dependent.reload
          expect(dependent.us_citizen).to eq true
          expect(dependent.naturalized_citizen).to eq false
          expect(dependent.eligible_immigration_status).to eq nil
          expect(dependent.indian_tribe_member).to eq true
          expect(dependent.tribal_state).to eq 'DC'
          expect(dependent.tribal_name).to eq 'Cherokee'
          expect(dependent.tribe_codes).to eq ['123']
        end
      end

      context "when dependent without us_citizen is applying for coverage" do
        let!(:is_applying_coverage) { true }
        let(:us_citizen) { false }


        it "should update tribe details " do
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(same_with_primary: "true"))
          application.reload
          dependent.reload
          expect(dependent.us_citizen).to eq false
          expect(dependent.naturalized_citizen).to eq false
          expect(dependent.eligible_immigration_status).to eq true
          expect(dependent.indian_tribe_member).to eq true
          expect(dependent.tribal_state).to eq 'DC'
          expect(dependent.tribal_name).to eq 'Cherokee'
          expect(dependent.tribe_codes).to eq ['123']
        end
      end

      context "when dependent is not applying for coverage" do
        let!(:is_applying_coverage) { false }
        let(:us_citizen) { false }
        let(:eligible_immigration_status) { true }

        before do
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(same_with_primary: "true", us_citizen: us_citizen, eligible_immigration_status: eligible_immigration_status))
          application.reload
          dependent.reload
        end

        it "should not nullify status/eligible immigration status" do
          expect(dependent.us_citizen).not_to be_nil
          expect(dependent.naturalized_citizen).not_to be_nil
          expect(dependent.eligible_immigration_status).not_to be_nil
        end

        it "should not update tribal details to nil" do
          expect(dependent.indian_tribe_member).not_to eq nil
          expect(dependent.tribal_state).not_to eq nil
          expect(dependent.tribal_name).not_to eq nil
          expect(dependent.tribe_codes).not_to eq []
        end
      end

      context 'when dependent is age off excluded' do
        let!(:is_applying_coverage) { true }
        let(:us_citizen) { true }

        before do
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(age_off_excluded: "true"))
          application.reload
          dependent.reload
        end

        it "should update age_off_excluded" do
          expect(dependent.age_off_excluded).to eq true
        end
      end

      context 'when dependent has ssn already and people tab is enabled' do
        let!(:is_applying_coverage) { true }
        let(:us_citizen) { true }

        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:people_tab).and_return(true)
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(ssn: "123456789", no_ssn: "1"))
          application.reload
          dependent.reload
        end

        it "should not update ssn and no_ssn" do
          expect(dependent.ssn).to eq nil
          expect(dependent.no_ssn).to eq "0"
        end
      end

      context 'when dependent has ssn already and people tab is disabled' do
        let!(:is_applying_coverage) { true }
        let(:us_citizen) { true }

        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:people_tab).and_return(false)
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(ssn: "123456789", no_ssn: "1"))
          application.reload
          dependent.reload
        end

        it "should update ssn and no_ssn" do
          expect(dependent.ssn).to eq "123456789"
          expect(dependent.no_ssn).to eq "1"
        end
      end

      context "when admin is updating applicant's ssn and QHP application is enabled" do
        let!(:is_applying_coverage) { true }
        let(:us_citizen) { true }

        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:people_tab).and_return(true)
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
          allow(subject).to receive(:can_update_ssn?).and_return(true)
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(ssn: "123456789", no_ssn: "1"))
          application.reload
          dependent.reload
        end

        it "should update ssn and no_ssn" do
          expect(dependent.ssn).to eq "123456789"
          expect(dependent.no_ssn).to eq "1"
        end
      end

      context "when admin is updating applicant's ssn to nil and no_ssn is checked and QHP application is enabled" do
        let!(:is_applying_coverage) { true }
        let(:us_citizen) { true }

        before do
          dependent.update(ssn: "123456789")
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:people_tab).and_return(true)
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
          allow(subject).to receive(:can_update_ssn?).and_return(true)
          patch :update, params: dependent_params.merge(applicant: applicant_params.merge(ssn: "", no_ssn: "1"))
          application.reload
          dependent.reload
        end

        it "should unset ssn and set no_ssn" do
          expect(dependent.ssn).to eq nil
          expect(dependent.no_ssn).to eq "1"
        end
      end
    end

    context "when the people tab flag is enabled" do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:people_tab).and_return(true)
      end

      it "should not update the DOB" do
        patch :update, params: update_params
        applicant.reload
        expect(applicant.dob).not_to eq Date.parse(update_params[:applicant][:dob])
        expect(applicant.dob).to eq TimeKeeper.date_of_record - 40.years
      end

      it "should update the applicant otherwise" do
        patch :update, params: update_params
        applicant.reload
        expect(applicant.first_name).to eq 'update'
      end

      it "should not raise any errors" do
        patch :update, params: update_params
        applicant.reload
        expect(applicant.valid?).to be_truthy
      end
    end

    context "when SSN is already taken by another person" do
      let(:existing_person) { FactoryBot.create(:person, :with_consumer_role, ssn: "123456789") }
      let(:update_params_with_taken_ssn) do
        {
          application_id: application.id,
          id: applicant2.id,
          applicant: {
            is_applying_coverage: true,
            first_name: 'Test',
            last_name: 'User',
            gender: 'male',
            dob: (TimeKeeper.date_of_record - 25.years).strftime("%Y-%m-%d"),
            ssn: "123456789", # Same SSN as existing_person
            relationship: 'spouse',
            is_consumer_role: false,
            addresses_attributes: {
              '0' => {
                kind: 'home',
                address_1: '123 Test St',
                city: 'Test City',
                state: 'DC',
                zip: '20001'
              }
            }
          }
        }
      end

      before do
        existing_person # Ensure the person with SSN exists
        # Mock the SSN taken operation to return that SSN is taken
        operation_instance = instance_double(::Operations::People::SsnTaken)
        allow(::Operations::People::SsnTaken).to receive(:new).and_return(operation_instance)
        allow(operation_instance).to receive(:call).and_return(
          double(success?: true, success: true, failure: nil)
        )
      end

      it "should fail to update when SSN is taken" do
        patch :update, params: update_params_with_taken_ssn
        expect(response).to have_http_status(302)

        # Should redirect back to applicants index or edit page due to form validation failure
        redirect_path = if EnrollRegistry.feature_enabled?(:qhp_application)
                          application_applicants_path(application)
                        else
                          edit_application_path(application)
                        end
        expect(response).to redirect_to(redirect_path)
      end

      it "should not update the applicant when SSN is taken" do
        original_ssn = applicant2.ssn
        patch :update, params: update_params_with_taken_ssn
        applicant2.reload
        expect(applicant2.ssn).to eq(original_ssn)
        expect(applicant2.ssn).not_to eq("123456789")
      end

      it "should handle SSN validation error properly" do
        # Mock form to test error handling
        form_instance = instance_double(FinancialAssistance::Forms::Applicant)
        allow(FinancialAssistance::Forms::Applicant).to receive(:new).and_return(form_instance)
        allow(form_instance).to receive(:is_dependent=)
        allow(form_instance).to receive(:application_id=)
        allow(form_instance).to receive(:applicant_id=)
        allow(form_instance).to receive(:save).and_return([false, ['ssn is already taken']])

        patch :update, params: update_params_with_taken_ssn
        expect(response).to have_http_status(302)
        # The controller redirects on both success and failure for update action
      end
    end
  end

  context "DELETE destroy" do
    let(:dependent1) { FactoryBot.create(:person) }
    let(:family_member_dependent) { FactoryBot.build(:family_member, person: dependent1, family: family)}
    let!(:applicant2) do
      FactoryBot.create(:applicant,
                        first_name: "James", last_name: "Bond", gender: "male", dob: Date.new(1993, 3, 8),
                        person_hbx_id: dependent1.hbx_id,
                        application: application,
                        family_member_id: family_member_dependent.id)
    end

    before do
      family.family_members << family_member_dependent
      family.save
      relation = PersonRelationship.new(relative: family.family_members.last.person, kind: "child")
      person.person_relationships << relation
      person.save
    end

    it "should redirect to edit application path" do
      delete :destroy, params: { application_id: application.id, id: applicant.id }
      expect(response).to redirect_to(edit_application_path(application))
    end

    it "should destroy the applicant" do
      delete :destroy, params: { application_id: application.id, id: applicant2.id }
      application.reload
      expect(application.active_applicants.where(id: applicant2.id).first).to be_nil
    end

    it "should not destroy the primary applicant" do
      expect(applicant.is_primary_applicant).to eq true
      delete :destroy, params: { application_id: application.id, id: applicant.id }
      application.reload
      expect(application.active_applicants.where(id: applicant.id).first).to eq applicant
    end

    it "should destroy the dependent" do
      expect(family.family_members.active.count).to eq 2
      delete :destroy, params: { application_id: application.id, id: applicant2.id }
      family.reload
      expect(family.family_members.active.count).to eq 1
    end

    it "should destroy the primary dependent" do
      expect(applicant.is_primary_applicant).to eq true
      expect(family.family_members.active.count).to eq 2
      delete :destroy, params: { application_id: application.id, id: applicant.id }
      family.reload
      expect(family.family_members.active.count).to eq 2
    end
  end

  context "GET age of applicant" do
    it "should return age of applicant", dbclean: :after_each do
      get :age_of_applicant, params: { application_id: application.id, applicant_id: applicant.id }, format: :js
      expect(response.body).to eq person.age_on(TimeKeeper.date_of_record).to_s
    end

    it "should not return age of applicant if the format is not js", dbclean: :after_each do
      get :age_of_applicant, params: { application_id: application.id, applicant_id: applicant.id }, format: :json
      expect(response.body).not_to eq person.age_on(TimeKeeper.date_of_record).to_s
    end
  end

  context "GET immigration_document_options" do
    it "should return age of applicant", dbclean: :after_each do
      get :immigration_document_options, params: { application_id: application.id,
                                                   target_type: "FinancialAssistance::Applicant",
                                                   applicant_id: applicant.id,
                                                   vlp_doc_target: "test"}, format: :js
      expect(response.status).to eq 200
    end

    it "should not return age of applicant if the format is not js", dbclean: :after_each do
      get :immigration_document_options, params: { application_id: application.id,
                                                   target_type: "FinancialAssistance::Applicant",
                                                   applicant_id: applicant.id,
                                                   vlp_doc_target: "test"}
      expect(response.status).not_to eq 200
    end
  end

  context "GET show_ssn" do
    let(:ssn) { "123456789" }
    let(:formatted_ssn) { "123-45-6789" }

    before do
      allow_any_instance_of(FinancialAssistance::ApplicantsController).to receive(:number_to_ssn).with(ssn).and_return(formatted_ssn)
    end

    context "when user is authorized and applicant exists" do
      before do
        applicant.update_attributes(ssn: ssn)

        allow_any_instance_of(FinancialAssistance::ApplicantsController).to receive(:authorize).and_return(true)
      end

      it "returns the formatted SSN in JSON response" do
        get :show_ssn, params: { application_id: application.id, id: applicant.id }

        expect(response).to have_http_status(200)
        parsed_response = JSON.parse(response.body)
        expect(parsed_response["payload"]).to eq(formatted_ssn)
        expect(parsed_response["status"]).to eq(200)
      end
    end

    context "when applicant does not exist" do
      before do
        allow_any_instance_of(FinancialAssistance::ApplicantsController).to receive(:authorize).and_return(true)
      end

      it "returns unauthorized status in JSON response" do
        get :show_ssn, params: { application_id: application.id, id: BSON::ObjectId.new }

        expect(response).to have_http_status(401)
        parsed_response = JSON.parse(response.body)
        expect(parsed_response["message"]).to eq("Unauthorized")
      end
    end

    context "when user is not authorized" do
      before do
        allow_any_instance_of(FinancialAssistance::ApplicantsController).to receive(:authorize).and_raise(Pundit::NotAuthorizedError.new("not authorized"))
      end

      it "returns unauthorized status in JSON response" do
        get :show_ssn, params: { application_id: application.id, id: applicant.id }

        expect(response).to have_http_status(401)
        parsed_response = JSON.parse(response.body)
        expect(parsed_response["message"]).to eq("Unauthorized")
      end
    end
  end
end

RSpec.describe FinancialAssistance::ApplicantsController, type: :controller do
  let(:date) { Date.today }
  let(:slash_date) { date.strftime('%m/%d/%Y') }
  let(:hyphen_date) { date.strftime('%Y-%m-%d') }
  let(:fake_date) { '12/47' }

  describe 'private methods' do
    controller(FinancialAssistance::ApplicantsController) do
      public :format_date_params
    end

    it 'format_date_params parses mm/dd/yyyy strings correctly' do
      model_params = { 'student_status_end_on' => slash_date }

      @controller.send(:format_date_params, model_params)
      expect(model_params['student_status_end_on']).to eq(date)
    end

    it 'format_date_params parses yyyy-mm-dd strings correctly' do
      model_params = { 'person_coverage_end_on' => hyphen_date }

      @controller.send(:format_date_params, model_params)
      expect(model_params['person_coverage_end_on']).to eq(date)
    end

    it 'format_date_params returns nil on invalid date' do
      model_params = { 'medicaid_cubcare_due_on' => fake_date }

      @controller.send(:format_date_params, model_params)
      expect(model_params['medicaid_cubcare_due_on']).to eq(nil) # invalid date returns nil
    end
  end
end
