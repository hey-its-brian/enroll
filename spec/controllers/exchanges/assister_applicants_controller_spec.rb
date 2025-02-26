# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Exchanges::AssisterApplicantsController do

  describe ".index" do
    let(:person) { FactoryBot.create(:person, :with_assister_role) }
    let(:user) { FactoryBot.create(:user, person: person) }
    let(:assister_role) { FactoryBot.create(:assister_role, person: person) }
    let(:assister_staff_state) { 'active' }
    let(:site) do
      FactoryBot.create(
        :benefit_sponsors_site,
        :with_benefit_market,
        :as_hbx_profile,
        site_key: ::EnrollRegistry[:enroll_app].settings(:site_key).item
      )
    end
    let(:assister_agency_profile) do
      FactoryBot.create(:benefit_sponsors_organizations_general_organization,
                        :with_assister_agency_profile, site: site).assister_agency_profile
    end
    let(:assister_staff) do
      FactoryBot.create(
        :assister_agency_staff_role,
        person: person,
        aasm_state: assister_staff_state,
        benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id
      )
    end
    let(:permission) { FactoryBot.create(:permission, :super_admin) }
    let(:hbx_profile) do
      FactoryBot.create(
        :hbx_profile,
        :normal_ivl_open_enrollment,
        us_state_abbreviation: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item,
        cms_id: "#{EnrollRegistry[:enroll_app].setting(:state_abbreviation).item.upcase}0"
      )
    end
    let(:hbx_staff_role) do
      person.create_hbx_staff_role(
        permission_id: permission.id,
        subrole: permission.name,
        hbx_profile: hbx_profile
      )
    end
    let(:hbx_admin_user) do
      user.tap { hbx_staff_role }
    end
    let(:logged_in_user) { hbx_admin_user }
    let(:market_kind) { :both }

    before do
      assister_role.update_attributes!(benefit_sponsors_assister_agency_profile_id: assister_agency_profile.id)
      person.create_assister_agency_staff_role(
        benefit_sponsors_assister_agency_profile_id: assister_role.benefit_sponsors_assister_agency_profile_id
      )
      assister_agency_profile.update_attributes!(primary_assister_role_id: assister_role.id, market_kind: market_kind)
      assister_role.approve!
    end

    it "should render index" do
      sign_in(hbx_admin_user)
      get :index, format: :js, xhr: true

      expect(assigns(:assister_applicants).size).to eq(1)
      expect(response).to have_http_status(:success)
      expect(response).to render_template("exchanges/assister_applicants/index")
    end

    context 'when hbx staff role missing' do
      let(:user) { instance_double("User", has_hbx_staff_role?: false) }

      it 'should redirect when hbx staff role missing' do
        sign_in(user)
        get :index, format: :js, xhr: true

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to('/exchanges/hbx_profiles')
      end
    end
  end

  describe ".edit" do
    let(:user) { instance_double("User", :has_hbx_staff_role? => true, :person => person) }
    let(:person) { instance_double("Person", :agent? => false) }
    let(:assister_role) {FactoryBot.create(:assister_role)}

    before :each do
      sign_in(user)
      get :edit, params: {id: assister_role.person.id}, format: :html, xhr: true
    end

    it "should render edit" do
      expect(assigns(:assister_applicant))
      expect(response).to have_http_status(:success)
      expect(response).to render_template("shared/assisters/applicant.html.erb", "layouts/single_column")
    end
  end

  describe ".update" do
    let(:user) { instance_double("User", :has_hbx_staff_role? => true, :person => person) }
    let(:person) { instance_double("Person", :agent? => false) }
    let(:assister_role) { FactoryBot.create(:assister_role) }

    before :all do
      @assister_agency_profile = FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile)
    end

    before :each do
      @assister_agency_profile.update!(primary_assister_role: assister_role)
      assister_role.update!(benefit_sponsors_assister_agency_profile_id: @assister_agency_profile.id)
      sign_in(user)
    end

    context 'carrier appointments, license, and reason' do
      it "should update for blank values" do
        put(
          :update,
          params: {
            "update" => "Update",
            id: assister_role.person.id,
            "person" => {
              "assister_role_attributes" => {
                "license" => "0",
                "training" => "0",
                "carrier_appointments" => {}
              }
            }
          }
        )
        assister_role.reload
        expect(assister_role.carrier_appointments).to eq({})
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to('/exchanges/hbx_profiles')
      end

      it 'should update for set values' do
        assister_role.update_attributes!(carrier_appointments: {})
        assister_role.reload
        expect(assister_role.carrier_appointments).to eq({})
        put(
          :update,
          params: {
            "update" => "Update",
            id: assister_role.person.id,
            "person" => {
              "assister_role_attributes" => {
                "license" => "1",
                "training" => "1",
                "carrier_appointments" => {"Aetna Health Inc" => "true", "United Health Care Insurance" => "true"}
              }
            }
          }
        )
        assister_role.reload
        expect(assister_role.carrier_appointments).to eq({"Aetna Health Inc" => "true", "United Health Care Insurance" => "true"})
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to('/exchanges/hbx_profiles')
      end
    end

    context 'when application denied' do
      before :each do
        put :update, params: {id: assister_role.person.id, deny: true}, format: :js
        assister_role.reload
      end

      it "should change applicant status to denied" do
        expect(assigns(:assister_applicant))
        expect(assister_role.aasm_state).to eq 'denied'
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to('/exchanges/hbx_profiles')
      end
    end

    context 'when application extended' do
      context "for denied application" do
        before :each do
          assister_role.deny!
          put :update, params: { id: assister_role.person.id, extend: true }, format: :js
          assister_role.reload
        end

        it 'should move application to application_extended' do
          expect(assigns(:assister_applicant))
          expect(assister_role.aasm_state).to eq 'application_extended'
        end

        it 'should redirect' do
          expect(response).to have_http_status(:redirect)
          expect(response).to redirect_to('/exchanges/hbx_profiles')
        end
      end

      context "for pending application" do
        context 'application_extended' do
          before :each do
            allow(assister_role).to receive(:is_primary_assister?).and_return(true)
            assister_role.pending!
            put :update, params: { id: assister_role.person.id, extend: true }, format: :js
            assister_role.reload
          end

          it 'should move application to application_extended' do
            expect(assigns(:assister_applicant))
            expect(assister_role.aasm_state).to eq 'application_extended'
          end

          it 'should redirect' do
            expect(response).to have_http_status(:redirect)
            expect(response).to redirect_to('/exchanges/hbx_profiles')
          end
        end

        context 'move to pending' do
          before :each do
            assister_role.update_attributes({ assister_agency_profile_id: @assister_agency_profile.id })
            allow(assister_role).to receive(:is_primary_assister?).and_return(true)
            assister_role.pending!
            put :update, params: { id: assister_role.person.id, pending: "pending", person: { assister_role_attributes: { training: true, carrier_appointments: {}, reason: "test"} } }, format: :js
            assister_role.reload
          end

          it 'should move application to assister_agency_pending' do
            expect(assigns(:assister_applicant))
            expect(assister_role.aasm_state).to eq 'assister_agency_pending'
          end

          it 'should store reason if any' do
            expect(assigns(:assister_applicant))
            expect(assister_role.reason).to eq 'test'
          end

          it 'should redirect' do
            expect(response).to have_http_status(:redirect)
            expect(response).to redirect_to('/exchanges/hbx_profiles')
          end
        end
      end

      context "for extended application" do
        before :each do
          assister_role.deny!
          assister_role.extend_application!
          put :update, params: { id: assister_role.person.id, extend: true }, format: :js
          assister_role.reload
        end

        it 'should move application to application_extended' do
          expect(assigns(:assister_applicant))
          expect(assister_role.aasm_state).to eq 'application_extended'
        end

        it 'should redirect' do
          expect(response).to have_http_status(:redirect)
          expect(response).to redirect_to('/exchanges/hbx_profiles')
        end
      end
    end

    context 'when application approved and applicant is not primary assister' do

      before :each do
        FactoryBot.create(:hbx_profile)
        @assister_agency_profile.update!(primary_assister_role: nil)
        put :update, params: {id: assister_role.person.id, approve: true, person: { assister_role_attributes: { training: true, carrier_appointments: {}} } }, format: :js
        assister_role.reload
      end

      it "should approve and change status to assister agency pending" do
        allow(assister_role).to receive(:assister_agency_profile).and_return(@assister_agency_profile)

        expect(assigns(:assister_applicant))
        expect(assister_role.aasm_state).to eq 'assister_agency_pending'
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to('/exchanges/hbx_profiles')
      end
    end

    context 'when applicant is a primary assister' do
      let(:assister_agency_profile) { FactoryBot.create(:benefit_sponsors_organizations_assister_agency_profile, primary_assister_role_id: assister_role.id) }

      context 'when application is approved' do
        before :each do
          assister_role.update_attributes({ assister_agency_profile_id: @assister_agency_profile.id })
          put :update, params: {id: assister_role.person.id, approve: true, person: { assister_role_attributes: { training: true, carrier_appointments: {}} }}, format: :js
          assister_role.reload
        end

        it "should change applicant status to active" do
          expect(assigns(:assister_applicant))
          expect(assister_role.aasm_state).to eq 'active'
          expect(response).to have_http_status(:redirect)
          expect(response).to redirect_to('/exchanges/hbx_profiles')
        end

        it "should have training as true in assister role attributes" do
          expect(assister_role.training).to eq true
        end
      end

      context 'when application is updated' do
        before :each do
          assister_role.update_attributes({ assister_agency_profile_id: @assister_agency_profile.id })
          assister_role.approve!
          put :update, params: {id: assister_role.person.id, update: true, person: { assister_role_attributes: { training: true, carrier_appointments: EnrollRegistry[:brokers].settings(:carrier_appointments).item }}}, format: :js
          assister_role.reload
        end

        it "should change applicant status to active" do
          expect(assigns(:assister_applicant))
          expect(assister_role.aasm_state).to eq 'active'
          expect(response).to have_http_status(:redirect)
          expect(response).to redirect_to('/exchanges/hbx_profiles')
          expect(assister_role.carrier_appointments.symbolize_keys).to eq(EnrollRegistry[:brokers].settings(:carrier_appointments).item)
        end

        it "should have training as true in assister role attributes" do
          expect(assister_role.training).to eq true
        end
      end

      context 'when assister carrier appointments enabled and application is pending' do
        context 'when application is pending' do
          let(:carrier_appointments_hash) do
            ca = {}
            EnrollRegistry[:brokers].setting(:carrier_appointments).item.stringify_keys.each do |k, _v|
              ca[k] = "true"
            end
            ca
          end

          before :each do
            allow(Settings.aca).to receive(:broker_carrier_appointments_enabled).and_return(true)
            assister_role.update_attributes({ assister_agency_profile_id: @assister_agency_profile.id })
            put :update, params: {id: assister_role.person.id, pending: true, person:  { assister_role_attributes: { training: true, carrier_appointments: {}} }}, format: :js
            assister_role.reload
          end

          it "all assister carrier appointments should be true" do
            expect(assister_role.carrier_appointments).to eq(carrier_appointments_hash)
          end

          it "should change applicant status to assister_agency_pending" do
            expect(assigns(:assister_applicant))
            expect(assister_role.aasm_state).to eq 'assister_agency_pending'
            expect(response).to have_http_status(:redirect)
            expect(response).to redirect_to('/exchanges/hbx_profiles')
          end

          it "should have training as true in assister role attributes" do
            expect(assister_role.training).to eq true
          end
        end
      end

      context 'when assister carrier appointments disabled and application is pending' do
        context 'when application is pending' do
          let(:carrier_appointments_hash) do
            EnrollRegistry[:brokers].setting(:carrier_appointments).item.stringify_keys
          end
          before :each do
            person_hash = ActionController::Parameters.new({ assister_role_attributes: { training: true, carrier_appointments: carrier_appointments_hash } }).permit!
            Settings.aca.broker_carrier_appointments_enabled = false
            assister_role.update_attributes({ assister_agency_profile_id: @assister_agency_profile.id })
            put :update, params: {id: assister_role.person.id, pending: true, person: person_hash}, format: :js
            assister_role.reload
          end

          it "assister carrier appointments should be user selected" do
            expect(assister_role.carrier_appointments.find {|_k, v| v == "true" }).to eq(carrier_appointments_hash.find {|_k, v| v == "true" })
          end

          it "should change applicant status to assister_agency_pending" do
            expect(assigns(:assister_applicant))
            expect(assister_role.aasm_state).to eq 'assister_agency_pending'
            expect(response).to have_http_status(:redirect)
            expect(response).to redirect_to('/exchanges/hbx_profiles')
          end

          it "should have training as true in assister role attributes" do
            expect(assister_role.training).to eq true
          end
        end
      end

      context 'when application is decertified' do
        before :each do
          assister_role.update_attributes({ assister_agency_profile_id: @assister_agency_profile.id })
          assister_role.approve!
          put :update, params: {id: assister_role.person.id, decertify: true}, format: :js
          assister_role.reload
        end

        it "should change applicant status to decertified" do
          expect(assigns(:assister_applicant))
          expect(assister_role.aasm_state).to eq 'decertified'
          expect(response).to have_http_status(:redirect)
          expect(response).to redirect_to('/exchanges/hbx_profiles')
        end
      end

      context 'when application is re-certified' do
        before :each do
          assister_role.update_attributes({ assister_agency_profile_id: @assister_agency_profile.id })
          assister_role.approve!
          assister_role.decertify!
          put :update, params: {id: assister_role.person.id, recertify: true}, format: :js
          assister_role.reload
        end

        it "should change applicant status to active" do
          expect(assigns(:assister_applicant))
          expect(assister_role.aasm_state).to eq 'active'
          expect(response).to have_http_status(:redirect)
          expect(response).to redirect_to('/exchanges/hbx_profiles')
        end
      end
    end
    context 'when assister invitation email is resent' do
      let(:invitation) { Invitation.new }
      before :each do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:resend_broker_email_button).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:prevent_concurrent_sessions).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:preferred_user_access).and_return(true)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:broker_role_consumer_enhancement).and_return(false)
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:sensor_tobacco_carrier_usage).and_return(false)
        put :update, params: {id: assister_role.person.id, sendemail: true}, format: :js
      end

      it "should call send_assister_invitation" do
        allow(Invitation).to receive(:create).and_return invitation
        expect(invitation).to receive(:send_assister_invitation!)
        Invitation.invite_assister!(assister_role)
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to('/exchanges/hbx_profiles')
      end
    end
  end

  describe '#update' do
    context "when:
      - person A exists with assister role and assister agency staff role associated with assister agency A
      - person B exists with a Consumer Role
      - person B has a User
      - person B has a assister agency staff role for assister agency A
      - person B has a assister role and assister agency staff role associated with assister agency B
      - admin approves person B's Assister Application" do

      let(:site) do
        FactoryBot.create(
          :benefit_sponsors_site,
          :with_benefit_market,
          :as_hbx_profile,
          site_key: ::EnrollRegistry[:enroll_app].settings(:site_key).item
        )
      end

      let(:assister_agency_organization_A) { FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_assister_agency_profile, site: site) }

      let(:assister_agency_profile_A) { assister_agency_organization_A.assister_agency_profile }

      let(:person_A) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }

      let(:assister_role_A) { FactoryBot.create(:assister_role, person: person_A, benefit_sponsors_assister_agency_profile_id: assister_agency_profile_A.id) }

      let(:aasr_1_A) do
        person_A.create_assister_agency_staff_role(
          benefit_sponsors_assister_agency_profile_id: assister_agency_profile_A.id
        )
      end

      let(:assister_agency_organization_B) { FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_assister_agency_profile, site: site) }

      let(:assister_agency_profile_B) { assister_agency_organization_B.assister_agency_profile }

      let(:person_B) do
        FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_hbx_staff_role)
      end

      let(:assister_role_B) { FactoryBot.create(:assister_role, person: person_B, benefit_sponsors_assister_agency_profile_id: assister_agency_profile_B.id) }

      let(:aasr_2_A) do
        basf = person_B.create_assister_agency_staff_role(
          benefit_sponsors_assister_agency_profile_id: assister_agency_profile_A.id
        )
        basf.assister_agency_accept!
        basf
      end

      let(:aasr_2_B) do
        basf = person_B.create_assister_agency_staff_role(
          benefit_sponsors_assister_agency_profile_id: assister_agency_profile_B.id
        )
        basf.assister_agency_accept!
        basf
      end

      let(:user) { FactoryBot.create(:user, :with_hbx_staff_role, person: person_B) }

      let(:input_params) do
        {
          id: person_B.id,
          approve: true,
          person: {
            assister_role_attributes: {
              training: true,
              carrier_appointments: {}
            }
          }
        }
      end

      before :each do
        allow(EnrollRegistry).to receive(:feature_enabled?).and_call_original
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:broker_role_consumer_enhancement).and_return(true)

        assister_agency_profile_A.update_attributes!(primary_assister_role_id: assister_role_A.id)
        aasr_1_A

        assister_agency_profile_B.update_attributes!(primary_assister_role_id: assister_role_B.id)
        aasr_2_A
        aasr_2_B

        sign_in(user)
        put :update, params: input_params, format: :js
      end

      it 'approves the assister, assister agency profile and assister agency staff role' do
        expect(assister_role_B.reload.active?).to be_truthy
        expect(assister_agency_profile_B.reload.is_approved?).to be_truthy
        expect(aasr_2_B.reload.active?).to be_truthy
      end
    end
  end
end
