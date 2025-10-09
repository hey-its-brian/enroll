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

  context "POST submit" do
    before do
      allow(controller).to receive(:haven_determination_is_enabled?).and_return(true)
      setup_faa_data
      allow(FinancialAssistance::Operations::Applications::MedicaidGateway::PublishApplication).to receive(:new).and_return(obj)
      allow(obj).to receive(:build_event).and_return(event)
      allow(event.success).to receive(:publish).and_return(true)
      controller.instance_variable_set(:@model, application.reload)
    end

    context "submit step with a valid but incomplete application" do
      before do
        application.update_attributes!(aasm_state: 'draft')
        allow(application).to receive(:complete?).and_return(false)
        allow(application).to receive(:save).and_return(true)
        allow(FinancialAssistance::Application).to receive(:find).and_return(application)
        allow(controller).to receive(:build_error_messages)

        post :submit_your_application_save, params: { id: application.id, application: application_valid_params.merge!("parent_living_out_of_home_terms" => "false") }
      end

      it "should render error page when there is an incomplete or already submitted application" do
        expect(response).to redirect_to(application_publish_error_application_path(application))
      end

      it "should set attestation terms to nil" do
        expect(application.reload.attestation_terms).to eq nil
      end
    end

    context "submit with a publish_result failure" do
      # receive_message_chain(:new, :call).and_return(success_result)
      let(:operation) { double new: double(call: double(failure: failure, success?: false)) }

      before do
        application.update_attributes!(aasm_state: 'submitted')
        allow(application).to receive(:complete?).and_return(true)
        allow(application).to receive(:may_submit?).and_return(true)
        allow(application).to receive(:submit!).and_return(true)
        allow(application).to receive(:save).and_return(true)
        allow(FinancialAssistance::Application).to receive(:find).and_return(application)
        allow(controller).to receive(:determination_request_class).and_return(operation)

        post :submit_your_application_save, params: { id: application.id, application: application_valid_params }
      end

      context "containing a failed Dry::Validation::Result" do
        let(:failure) do
          Dry::Validation::Result.new(double(message_set: [], to_h: {})) do |r|
            r.add_error(Dry::Validation::Message.new("length must be within 10 - 15",
                                                     path: [:applicants, 0, :phones, 0, :full_phone_number]))
          end
        end

        it 'redirects to application_publish_error_application_path' do
          expect(response).to redirect_to(application_publish_error_application_path(application.id))
        end

        it 'builds the flash message correctly' do
          expect(flash[:error].first).to eql("The 1st applicants's 1st phones's full phone number: length must be within 10 - 15.")
        end
      end

      context "containing an Exception" do
        let(:failure) do
          StandardError.new("test")
        end

        it 'builds the flash message with the exception text' do
          expect(flash[:error]).to eql('test')
        end
      end

      context "containing with a string" do
        let(:failure) { "big big problem" }

        it 'builds the flash message with the string' do
          expect(flash[:error]).to eql('Submission Error: big big problem')
        end
      end
    end
    context "when params has application key" do
      let(:success_result) { double(success?: true)}

      let!(:create_home_address) do
        [application, application2].each do |applin|
          applin.applicants.first.update_attributes!(is_primary_applicant: true)
          address_attributes = {
            kind: 'home',
            address_1: '3 Awesome Street',
            address_2: '#300',
            city: FinancialAssistanceRegistry[:enroll_app].setting(:contact_center_city).item,
            state: FinancialAssistanceRegistry[:enroll_app].setting(:state_abbreviation).item,
            zip: FinancialAssistanceRegistry[:enroll_app].setting(:contact_center_zip_code).item
          }
          if EnrollRegistry[:enroll_app].setting(:geographic_rating_area_model).item == 'county'
            address_attributes.merge!(
              county: FinancialAssistanceRegistry[:enroll_app].setting(:contact_center_county).item
            )
          end
          financial_assistance_address = ::FinancialAssistance::Locations::Address.new(address_attributes)
          applin.reload
          applin.applicants.each do |applicant|
            applicant.addresses << financial_assistance_address
            applicant.save!
          end
          family_id = applin.family_id
          family = Family.find(family_id) if family_id.present?
          next unless family
          family.family_members.each do |fm|
            main_app_address = Address.new(address_attributes)
            fm.person.addresses << main_app_address
            fm.person.save!
          end
        end
      end

      before do
        applicant1 = application2.applicants.first
        applicant2 = application2.applicants.last
        application2.add_or_update_relationships(applicant1, applicant2, "spouse")
      end

      it "When model is saved" do
        post :submit_your_application_save, params: { id: application.id, application: application_valid_params }
        expect(application.save).to eq true
      end

      context "when the request type is invalid" do
        it "should be an error when csv" do
          post :submit_your_application_save, params: { id: application.id, application: application_valid_params }, format: :csv
          expect(response.status).to eq 406
          expect(response.body).to eq "Unsupported format"
          expect(response.media_type).to eq "text/csv"
        end

        it "should be an error when js" do
          post :submit_your_application_save, params: { id: application.id, application: application_valid_params }, format: :js
          expect(response.status).to eq 406
          expect(response.body).to eq "Unsupported format"
        end

        it "should be an error when xml" do
          post :submit_your_application_save, params: { id: application.id, application: application_valid_params }, format: :xml
          expect(response.status).to eq 406
          expect(response.body).to eq "<error>Unsupported format</error>"
        end
      end

      it "should fail during publish application and redirects to error_page" do
        application2.ensure_relationship_with_primary(application2.applicants[1], 'spouse')
        post :submit_your_application_save, params: { id: application2.id, application: application_valid_params }
        expect(flash[:error]).to match(/Submission Error: /)
        expect(response).to redirect_to(application_publish_error_application_path(application2))
      end

      it "should successfully publish application and redirects to wait_for_eligibility" do
        application.update_attributes!(aasm_state: 'submitted')
        application.reload
        allow(application).to receive(:complete?).and_return(true)
        allow(application).to receive(:may_submit?).and_return(true)
        allow(application).to receive(:submit!).and_return(true)
        allow(FinancialAssistance::Operations::Application::RequestDetermination).to receive_message_chain(:new, :call).and_return(success_result)
        allow(FinancialAssistance::Application).to receive(:find).and_return(application)
        post :submit_your_application_save, params: { id: application.id, application: application_valid_params }
        expect(response).to redirect_to(wait_for_eligibility_response_application_path(application))
      end
    end

    it "should re if model is not saved" do
      post :submit_your_application_save, params: { id: application.id }
      expect(response).to render_template 'financial_assistance/applications/submit_your_application'
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
