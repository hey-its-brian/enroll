# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::IncomesController, dbclean: :after_each, type: :controller do
  routes { FinancialAssistance::Engine.routes }

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:consumer_role) { person.consumer_role }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_family_member) { family.primary_applicant }

  let!(:user) { FactoryBot.create(:user, :person => person) }
  let!(:family_id) { family.id }
  let!(:family_member_id) { primary_family_member.id }
  let!(:application) { FactoryBot.create(:application, family_id: family_id, aasm_state: "draft",effective_date: TimeKeeper.date_of_record) }
  let!(:applicant) { FactoryBot.create(:applicant, application: application, family_member_id: family_member_id) }
  let!(:income) do
    income = FactoryBot.build(:financial_assistance_income)
    applicant.incomes << income
    income
  end
  let!(:valid_job_income_params){ {"kind" => "wages_and_salaries", "employer_name" => "sfd", "amount" => "50001", "frequency_kind" => "quarterly", "start_on" => "11/08/2017", "end_on" => "11/08/2018", "employer_address" => {"kind" => "work", "address_1" => "2nd Main St", "address_2" => "sfdsf", "city" => "Washington", "state" => "DC", "zip" => "35467"}, "employer_phone" => {"kind" => "work", "full_phone_number" => "(301)-848-8053"}} }
  let!(:valid_self_employed_income_params){ {"kind" => "net_self_employment", "amount" => "23", "frequency_kind" => "monthly", "start_on" => "11/01/2017", "end_on" => "11/23/2017"} }
  let!(:valid_unemployment_income_params){ {"kind" => "unemployment_income", "amount" => "45", "frequency_kind" => "biweekly", "start_on" => "11/01/2017", "end_on" => "11/30/2017"}}
  let!(:valid_other_income_params){ {"kind" => "alimony_and_maintenance", "amount" => "45", "frequency_kind" => "biweekly", "start_on" => "11/01/2017", "end_on" => "11/30/2017"}}
  let!(:valid_income_params){ {"kind" => "capital_gains", "amount" => "34.8", "frequency_kind" => "monthly", "start_on" => "09/04/2017", "end_on" => "09/24/2017", "employer_name" => ""} }
  let!(:invalid_income_params){  {"kind" => "ppp", "amount" => "45.3", "frequency_kind" => "monthly", "start_on" => "09/04/2017", "end_on" => "09/24/2017", "employer_name" => ""} }
  let(:income_employer_address_params){ {"address_1" => "23 main st ne", "address_2" => "", "city" => "washington", "state" => "dc", "zip" => "12343"}}
  let(:income_employer_phone_params) {{"full_phone_number" => ""}}

  before do
    consumer_role.move_identity_documents_to_verified
    sign_in(user)
  end

  context "GET index" do

    context "when application is not reviewable" do
      it "should render template financial assistance" do
        get :index, params: { application_id: application.id, applicant_id: applicant.id }
        if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
          expect(response).to render_template(:financial_assistance_progress)
        else
          expect(response).to render_template(:financial_assistance_nav)
        end
      end
    end

    context "when application is reviewable" do
      let!(:reviewable_application) { FactoryBot.create(:application, family_id: family_id, aasm_state: "submitted", effective_date: TimeKeeper.date_of_record) }
      let!(:reviewable_applicant) { FactoryBot.create(:applicant, application: reviewable_application, family_member_id: family_member_id) }

      before do
        # Mock the qhp_application_feature_enabled? method to return true
        allow_any_instance_of(FinancialAssistance::IncomesController).to receive(:qhp_application_feature_enabled?).and_return(true)
      end

      it "should redirect back to previous page or fallback location via before_action" do
        # Set up the referer to test redirect_back behavior
        request.env["HTTP_REFERER"] = "http://example.com/previous_page"
        get :index, params: { application_id: reviewable_application.id, applicant_id: reviewable_applicant.id }
        expect(response).to redirect_to("http://example.com/previous_page")
      end

      it "should redirect to fallback location when no referer is present" do
        # No referer set, should use fallback location
        get :index, params: { application_id: reviewable_application.id, applicant_id: reviewable_applicant.id }
        expect(response).to redirect_to('/insured/sbm/applications')
      end

      it "should not render the template when redirecting" do
        get :index, params: { application_id: reviewable_application.id, applicant_id: reviewable_applicant.id }
        if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
          expect(response).not_to render_template(:financial_assistance_progress)
        else
          expect(response).not_to render_template(:financial_assistance_nav)
        end
      end

      it "should redirect before authorization occurs" do
        # The before_action should trigger before authorize is called
        expect_any_instance_of(FinancialAssistance::IncomesController).not_to receive(:authorize)
        get :index, params: { application_id: reviewable_application.id, applicant_id: reviewable_applicant.id }
        expect(response).to be_redirect
      end

      context "when qhp_application_feature is disabled" do
        before do
          allow_any_instance_of(FinancialAssistance::IncomesController).to receive(:qhp_application_feature_enabled?).and_return(false)
        end

        it "should not redirect and proceed with normal flow" do
          get :index, params: { application_id: reviewable_application.id, applicant_id: reviewable_applicant.id }
          if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
            expect(response).to render_template(:financial_assistance_progress)
          else
            expect(response).to render_template(:financial_assistance_nav)
          end
        end
      end
    end
  end

  context "POST new" do
    it "should load template work flow steps" do
      post :new, params: { application_id: application.id, applicant_id: applicant.id }
      expect(response).to render_template(:financial_assistance_nav)
      expect(response).to render_template 'other'
    end
  end

  context "create job income" do
    it "should create a job income  instance" do
      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_job_income_params }, format: :js
      expect(applicant.incomes.count).to eq 1
    end
    it "should able to save an job income instance with the 'to' field blank " do
      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_job_income_params }, format: :js
      valid_job_income_params["end_on"] = nil
      expect(applicant.incomes.count).to eq 1
    end
  end

  context "create self employed income" do
    it "should create a self employed income  instance" do
      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_self_employed_income_params }, format: :js
      expect(applicant.incomes.count).to eq 1
    end
    it "should able to save an self employed income instance with the 'to' field blank " do
      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_self_employed_income_params }, format: :js
      valid_self_employed_income_params["end_on"] = nil
      expect(applicant.incomes.count).to eq 1
    end
  end

  context "create unemployment income" do
    it "should create an unemployment income instance" do
      skip "skipped: unemployment income feature not enabled" unless FinancialAssistanceRegistry[:unemployment_income].enabled?

      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_unemployment_income_params }, format: :js
      expect(applicant.incomes.count).to eq 1
    end
    it "should able to save an unemployment income instance with the 'to' field blank " do
      skip "skipped: unemployment income feature not enabled" unless FinancialAssistanceRegistry[:unemployment_income].enabled?

      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_unemployment_income_params }, format: :js
      valid_unemployment_income_params["end_on"] = nil
      expect(applicant.incomes.count).to eq 1
    end
  end

  context "create other income" do
    it "should create a other income  instance" do
      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_other_income_params }, format: :js
      expect(applicant.incomes.count).to eq 1
    end
    it "should able to save an other income instance with the 'to' field blank " do
      post :create, params: { application_id: application.id, applicant_id: applicant.id, financial_assistance_income: valid_other_income_params }, format: :js
      valid_other_income_params["end_on"] = nil
      expect(applicant.incomes.count).to eq 1
    end
  end

  context "valid income id #destroy" do
    it "should create new income" do
      expect(applicant.incomes.count).to eq 1
      delete :destroy, params: { application_id: application.id, applicant_id: applicant.id, id: income.id }
      applicant.reload
      expect(applicant.incomes.count).to eq 0
    end
  end

  context "invalid income id #destroy" do
    it "should not throw an exception" do
      expect(applicant.incomes.count).to eq 1
      delete :destroy, params: { application_id: application.id, applicant_id: applicant.id, id: '55555' }
      applicant.reload
      expect(response).to_not have_http_status(500)
    end
  end
end
