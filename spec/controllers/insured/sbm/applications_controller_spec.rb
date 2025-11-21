# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Insured::Sbm::ApplicationsController, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role)}
  let!(:user) { FactoryBot.create(:user, :person => person) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let!(:hbx_profile) { FactoryBot.create(:hbx_profile, :open_enrollment_coverage_period) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }
  before do
    family.primary_person.consumer_role.move_identity_documents_to_verified
    sign_in user
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(false)
  end

  describe 'GET #current_applications' do
    it 'should render the current_applications template' do
      get :current_applications
      expect(response).to render_template('current_applications')
    end

    it 'should assign the applicable year' do
      get :current_applications
      expect(assigns(:applicable_year)).not_to be_nil
    end

    it 'should assign the previous year' do
      get :current_applications
      expect(assigns(:previous_year)).not_to be_nil
    end

    context 'when the open enrollment is active' do
      before do
        HbxProfile.current_hbx.benefit_sponsorship.benefit_coverage_periods.each do |bcp|
          bcp.update_attributes!(open_enrollment_start_on: TimeKeeper.date_of_record - 1.day)
        end
      end

      it 'should not set the prospective year' do
        get :current_applications
        expect(assigns(:prospective_year)).to be_nil
      end
    end

    context 'when the open enrollment is not active' do
      before do
        HbxProfile.current_hbx.benefit_sponsorship.benefit_coverage_periods.each do |bcp|
          bcp.update_attributes!(open_enrollment_start_on: TimeKeeper.date_of_record + 1.day)
        end
      end

      it 'should set the prospective year' do
        get :current_applications
        expect(assigns(:prospective_year)).not_to be_nil
      end

      it 'should not set the prospective application' do
        get :current_applications
        expect(assigns(:prospective_application)).to be_nil
      end

      it 'should not set the oe start date when prospective application is not present' do
        get :current_applications
        expect(assigns(:oe_start_date)).to be_nil
      end

      context 'when a prospective application is present and not under OE' do
        let(:application) { FactoryBot.create(:individual_market_application, :determined,:with_applicants, family_id: family.id, assistance_year: TimeKeeper.date_of_record.year + 1) }
        before do
          application
          get :current_applications
        end

        context 'when the application is determined' do
          it 'should set the prospective application' do
            expect(assigns(:prospective_application)).to eq(application)
          end

          it 'should set the oe start date' do
            expect(assigns(:oe_start_date)).not_to be_nil
          end
        end
      end

      it 'should not set the prospective application when it is not determined' do
        FactoryBot.create(:individual_market_application, :initial, :with_applicants, family_id: family.id, assistance_year: TimeKeeper.date_of_record.year + 1)
        get :current_applications
        expect(assigns(:prospective_application)).to be_nil
      end
    end
  end

  describe 'GET #evidences' do
    let(:person2) { FactoryBot.create(:person, :with_consumer_role)}
    let(:application) do
      FactoryBot.create(
        :financial_assistance_application,
        family_id: family.id,
        aasm_state: 'determined',
        submitted_at: Time.now,
        assistance_year: TimeKeeper.date_of_record.year
      )
    end

    let(:applicant1) do
      FactoryBot.create(
        :financial_assistance_applicant,
        family_member_id: family.primary_applicant.id,
        person_hbx_id: person.hbx_id,
        application: application
      )
    end

    let(:applicant2) do
      FactoryBot.create(
        :financial_assistance_applicant,
        family_member_id: family.primary_applicant.id,
        person_hbx_id: person2.hbx_id,
        application: application
      )
    end
    let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant1) }
    let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant1) }
    let(:aptc_csr_eligibility2) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant2) }
    let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }
    let(:esi_evidence) { FactoryBot.create(:esi_mec_evidence, :with_verification_histories, :pending, eligibility: aptc_csr_eligibility) }
    let(:esi_evidence2) { FactoryBot.create(:esi_mec_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility2, due_on: Date.current + 40.days) }
    let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories, :verified, eligibility: aptc_csr_eligibility) }
    let(:application_gid) { application.to_global_id.to_s }

    before do
      ssn_evidence
      esi_evidence
      esi_evidence2
      income_evidence
      family.assign_latest_application_gid
      family.save!
    end

    context 'when application exists and it is eligible to display evidences' do
      before do
        allow(controller).to receive(:ineligible_to_view_evidences?).with(application.family).and_return(false)
        get :evidences, params: { id: application.id, application_gid: application_gid }
      end

      it 'assigns the application' do
        expect(assigns(:application)).to eq(application)
      end

      it 'assigns applicants from the application' do
        expect(assigns(:applicants)).to eq(application.applicants)
      end

      it 'assigns sorted applicants by status and due date' do
        expect(assigns(:sorted_applicants)).to eq([applicant1, applicant2])
      end

      it 'assigns flattened action items from all applicants' do
        expect(assigns(:action_items).map(&:evidence_item_key)).to eq([:social_security_number_evidence, :esi_mec_evidence])
      end

      it 'renders the evidences template' do
        expect(response).to render_template('evidences')
      end

      it 'assigns the family from the application' do
        expect(assigns(:family)).to eq(application.family)
      end
    end

    context 'when application exists and it is ineligible to display evidences' do
      before do
        allow(controller).to receive(:ineligible_to_view_evidences?).with(application.family).and_return(true)
        get :evidences, params: { id: application.id, application_gid: application_gid }
      end

      it 'redirects to verification page' do
        expect(response).to redirect_to(verification_insured_families_url(family))
      end
    end

    context 'when application does not exist' do
      let(:invalid_gid) { 'invalid-gid' }

      before do
        allow(GlobalID::Locator).to receive(:locate).with(invalid_gid).and_return(nil)
        get :evidences, params: { id: application.id, application_gid: invalid_gid }
      end

      it 'sets error flash message' do
        expect(flash[:error]).to eq('Application not found')
      end

      it 'redirects to current applications page' do
        expect(response).to redirect_to(current_applications_insured_sbm_applications_path)
      end
    end

    context 'applicant sorting with nil due dates' do
      before do
        allow(applicant1).to receive(:earliest_due_date).and_return(nil)
        allow(applicant2).to receive(:earliest_due_date).and_return(Date.current + 5.days)
        allow(controller).to receive(:ineligible_to_view_evidences?).with(application.family).and_return(false)
        get :evidences, params: {  id: application.id, application_gid: application_gid }
      end

      it 'sorts applicants with nil due dates last' do
        expect(assigns(:sorted_applicants)).to eq([applicant1, applicant2])
      end
    end
  end

  describe 'GET #index' do
    let(:filtered_applications_value) do
      {
        applications: [qhp_application, faa_application],
        filtered_applications: [faa_application, qhp_application],
        recent_determined_hbx_id: nil
      }
    end
    let(:success_result) { Dry::Monads::Result::Success.new(filtered_applications_value) }
    let(:failure_result) { Dry::Monads::Result::Failure.new(errors: ['Some error']) }
    let(:query_operation) { instance_double(Operations::Sbm::Applications::QueryFilteredApplications) }
    let!(:qhp_application) { FactoryBot.create(:individual_market_application, :initial, :with_applicants, family_id: family.id) }
    let(:faa_application) do
      FactoryBot.create(:financial_assistance_application,
                        family_id: family.id,
                        aasm_state: 'draft',
                        assistance_year: TimeKeeper.date_of_record.year,
                        effective_date: Date.today)
    end
    let(:copyable_faa_application_ids) { [faa_application.id] }

    before do
      allow(Operations::Sbm::Applications::QueryFilteredApplications).to receive(:new).and_return(query_operation)
      allow(family).to receive(:fetch_copyable_faa_application_ids).and_return(copyable_faa_application_ids)
    end

    context 'when query operation succeeds' do
      before do
        allow(query_operation).to receive(:call).and_return(success_result)
        get :index
      end

      it 'assigns applications from the operation result' do
        expect(assigns(:applications)).to eq([qhp_application, faa_application])
      end

      it 'assigns the application year' do
        expect(assigns(:applicable_year)).not_to be_nil
      end

      it 'assigns filtered applications from the operation result' do
        expect(assigns(:filtered_applications)).to eq([faa_application, qhp_application])
      end

      it 'should not assigns recent determined HBX ID from the operation result' do
        expect(assigns(:recent_determined_hbx_id)).to eq(nil)
      end

      it 'renders the index template' do
        expect(response).to render_template('index')
      end
    end

    context 'when query operation fails' do
      before do
        allow(query_operation).to receive(:call).and_return(failure_result)
      end

      it 'returns unprocessable_entity status for json format' do
        get :index, format: :json
        expect(response.status).to eq(422)
      end

      it 'renders html format' do
        get :index
        expect(response.content_type).to include('text/html')
      end
    end

    context 'with filter parameters' do
      let(:filter_year) { '2023' }

      it 'passes filter parameters to the operation' do
        expect(query_operation).to receive(:call).with(
          {
            family_id: family.id,
            filter_year: filter_year
          }
        ).and_return(success_result)

        get :index, params: { filter: { year: filter_year } }
      end
    end

    context 'when bs4_consumer_flow feature is enabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(true)
        allow(query_operation).to receive(:call).and_return(success_result)
        get :index
      end

      it 'enables bs4 layout' do
        expect(assigns(:bs4)).to be true
      end
    end

    context 'when bs4_consumer_flow feature is disabled' do
      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:bs4_consumer_flow).and_return(false)
        allow(query_operation).to receive(:call).and_return(success_result)
        get :index
      end

      it 'does not enable bs4 layout' do
        expect(assigns(:bs4)).to be_nil
      end
    end
  end
end
