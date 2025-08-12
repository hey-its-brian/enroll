# frozen_string_literal: true

RSpec.describe Eligibilities::Evidences::EvidencesController, type: :controller do
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  let!(:fake_person) { FactoryBot.create(:person, :with_consumer_role) }
  let!(:fake_user) { FactoryBot.create(:user, :person => fake_person) }
  let!(:fake_family) { FactoryBot.create(:family, :with_primary_family_member, person: fake_person) }
  let!(:fake_family_member) { fake_family.family_members.first }

  let!(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
  let!(:admin_user) { FactoryBot.create(:user, :with_hbx_staff_role, :person => admin_person) }
  let!(:permission) { FactoryBot.create(:permission, :super_admin) }
  let!(:update_admin) { admin_person.hbx_staff_role.update_attributes(permission_id: permission.id) }

  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }
  let(:determination) { ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family) }
  let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant, key: :individual_market_eligibility) }

  let(:faa_application) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      aasm_state: 'determined',
      submitted_at: Time.now,
      assistance_year: TimeKeeper.date_of_record.year
    )
  end

  let(:applicant) do
    FactoryBot.create(:applicant,
                      application: faa_application,
                      dob: TimeKeeper.date_of_record - 40.years,
                      is_primary_applicant: true,
                      family_member_id: primary_applicant.id,
                      person_hbx_id: person.hbx_id,
                      first_name: person.first_name,
                      last_name: person.last_name,
                      gender: person.gender,
                      ssn: person.ssn,
                      addresses: [FactoryBot.build(:financial_assistance_address)])
  end

  context 'admin' do
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      income_evidence
      ssn_evidence
      family.assign_latest_application_gid
      family.save!
      sign_in(admin_user)
    end

    context 'put #update' do
      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          admin_action: 'verify',
          verification_reason: 'Document in EnrollApp'
        }
      end

      context 'with valid params and successful operation' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_new_verifications_household_summary).and_return(true)
        end

        it 'updates evidence verification status' do
          put :update, params: params
          expect(flash[:success]).to eq("Income evidence successfully verified.")
        end

        it 'redirects to verification detail path' do
          put :update, params: params
          expect(response).to redirect_to(verification_detail_insured_families_path(
                                            person_id: params[:person_id],
                                            eligibility_kind: params[:eligibility_kind],
                                            evidence_key: params[:evidence_key]
                                          ))
        end

        it 'calls build determination after successful update' do
          expect(Operations::Eligibilities::BuildFamilyDetermination).to receive_message_chain(:new, :call).with(family: family)
          put :update, params: params
        end
      end

      context 'with valid params but failed operation' do
        before do
          allow(Operations::Eligibilities::Evidences::Update).to receive_message_chain(:new, :call)
            .and_return(double(success?: false, failure: "Operation failed"))
        end

        it 'displays error message when operation fails' do
          put :update, params: params
          expect(flash[:error]).to eq("Operation failed")
        end
      end

      context 'with invalid verification reason' do
        let!(:invalid_params) do
          params.merge(verification_reason: 'Invalid Reason')
        end

        it 'displays error message for invalid verification reason' do
          put :update, params: invalid_params
          expect(flash[:error]).to eq("Please provide a verification reason.")
        end
      end

      context 'with return_for_deficiency admin action' do
        let!(:reject_params) do
          params.merge(admin_action: 'return_for_deficiency', verification_reason: 'Illegible')
        end

        it 'rejects evidence with valid reason' do
          put :update, params: reject_params
          expect(flash[:success]).to eq("Income evidence rejected.")
        end
      end

      context 'with uneditable application state' do
        before do
          faa_application.update_attributes!(aasm_state: 'cancelled')
        end

        it 'redirects to applications path with alert message' do
          put :update, params: params
          expect(flash[:alert]).to be_present
          expect(response).to redirect_to(current_applications_insured_sbm_applications_path)
        end
      end

      context 'with missing evidence' do
        let!(:invalid_params) do
          params.merge(id: 'invalid_id')
        end

        it 'handles evidence not found' do
          put :update, params: invalid_params
          expect(flash[:error]).to eq("Evidence not found")
        end
      end

      context 'with missing eligibility' do
        let!(:invalid_params) do
          params.merge(eligibility_id: 'invalid_id')
        end

        it 'handles eligibility not found' do
          put :update, params: invalid_params
          expect(flash[:error]).to eq("Eligibility not found")
        end
      end

      context 'with missing applicant' do
        let!(:invalid_params) do
          params.merge(applicant_id: 'invalid_id')
        end

        it 'handles applicant not found' do
          put :update, params: invalid_params
          expect(flash[:error]).to eq("Applicant not found")
        end
      end

      context 'with missing application' do
        let!(:invalid_params) do
          params.merge(application_gid: 'invalid_gid')
        end

        it 'handles application not found' do
          put :update, params: invalid_params
          expect(flash[:error]).to eq("Application not found")
        end
      end
    end

    context 'put #extend_due_date' do
      let!(:extend_params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          extension_period: 30
        }
      end

      context 'with valid params and successful operation' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_new_verifications_household_summary).and_return(true)
          allow(income_evidence).to receive(:extend_due_date).and_return(true)
        end

        it 'extends evidence due date' do
          put :extend_due_date, params: extend_params
          expect(flash[:success]).to include("due date extended")
        end

        it 'redirects to verification detail path' do
          put :extend_due_date, params: extend_params
          expect(response).to redirect_to(verification_detail_insured_families_path(
                                            person_id: extend_params[:person_id],
                                            eligibility_kind: extend_params[:eligibility_kind],
                                            evidence_key: extend_params[:evidence_key]
                                          ))
        end

        it 'calls build determination after successful extension' do
          expect(Operations::Eligibilities::BuildFamilyDetermination).to receive_message_chain(:new, :call).with(family: family)
          put :extend_due_date, params: extend_params
        end
      end

      context 'with specific due date' do
        let!(:specific_date_params) do
          extend_params.merge(due_on: (Date.current + 45.days).strftime('%Y-%m-%d'))
                       .except(:extension_period)
        end

        before do
          allow(income_evidence).to receive(:extend_due_date).and_return(true)
        end

        it 'extends evidence to specific due date' do
          put :extend_due_date, params: specific_date_params
          expect(flash[:success]).to include("due date extended")
        end
      end

      context 'with valid params but failed operation' do
        before do
          allow(Operations::Eligibilities::Evidences::ExtendDueDate).to receive_message_chain(:new, :call).and_return(double(success?: false, failure: "Operation failed"))
        end

        it 'displays error message when operation fails' do
          put :extend_due_date, params: extend_params
          expect(flash[:danger]).to eq("Operation failed")
        end
      end

      context 'with uneditable application state' do
        before do
          faa_application.update_attributes!(aasm_state: 'cancelled')
        end

        it 'redirects to applications path with alert message' do
          put :extend_due_date, params: extend_params
          expect(flash[:alert]).to be_present
          expect(response).to redirect_to(current_applications_insured_sbm_applications_path)
        end
      end

      context 'with missing evidence' do
        let!(:invalid_params) do
          extend_params.merge(id: 'invalid_id')
        end

        it 'handles evidence not found' do
          put :extend_due_date, params: invalid_params
          expect(flash[:error]).to eq("Evidence not found")
        end
      end

      context 'with missing eligibility' do
        let!(:invalid_params) do
          extend_params.merge(eligibility_id: 'invalid_id')
        end

        it 'handles eligibility not found' do
          put :extend_due_date, params: invalid_params
          expect(flash[:error]).to eq("Eligibility not found")
        end
      end

      context 'with missing applicant' do
        let!(:invalid_params) do
          extend_params.merge(applicant_id: 'invalid_id')
        end

        it 'handles applicant not found' do
          put :extend_due_date, params: invalid_params
          expect(flash[:error]).to eq("Applicant not found")
        end
      end

      context 'with missing application' do
        let!(:invalid_params) do
          extend_params.merge(application_gid: 'invalid_gid')
        end

        it 'handles application not found' do
          put :extend_due_date, params: invalid_params
          expect(flash[:error]).to eq("Application not found")
        end
      end
    end

    context 'put #fed_hub_request' do
      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          admin_action: 'hub_request'
        }
      end

      context 'with income evidence valid params and successful operation' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_new_verifications_household_summary).and_return(true)
        end

        it 'updates evidence verification status' do
          put :fed_hub_request, params: params
          expect(flash[:success]).to eq("request submitted successfully")
        end

        it 'redirects to verification detail path' do
          put :fed_hub_request, params: params
          expect(response).to redirect_to(verification_detail_insured_families_path(
                                            person_id: params[:person_id],
                                            eligibility_kind: params[:eligibility_kind],
                                            evidence_key: params[:evidence_key]
                                          ))
        end

        it 'calls build determination after successful update' do
          expect(Operations::Eligibilities::BuildFamilyDetermination).to receive_message_chain(:new, :call).with(family: family)
          put :fed_hub_request, params: params
        end
      end

      context 'with ssn evidence valid params and successful operation' do
        before do
          params.merge!(eligibility_id: ivl_eligibility.id, id: ssn_evidence.id, eligibility_kind: 'individual_market_eligibility', evidence_key: :social_security_number_evidence)
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_new_verifications_household_summary).and_return(true)
        end

        it 'updates evidence verification status' do
          put :fed_hub_request, params: params
          expect(flash[:success]).to eq("request submitted successfully")
        end

        it 'redirects to verification detail path' do
          put :fed_hub_request, params: params
          expect(response).to redirect_to(verification_detail_insured_families_path(
                                            person_id: params[:person_id],
                                            eligibility_kind: params[:eligibility_kind],
                                            evidence_key: params[:evidence_key]
                                          ))
        end

        it 'calls build determination after successful update' do
          expect(Operations::Eligibilities::BuildFamilyDetermination).to receive_message_chain(:new, :call).with(family: family)
          put :fed_hub_request, params: params
        end
      end

      context 'with valid params but failed operation' do
        before do
          allow_any_instance_of(FinancialAssistance::Evidences::IncomeEvidence).to receive(:call_hub).and_return(double(success?: false, failure: "Hub call failed"))
        end

        it 'displays error message when operation fails' do
          put :fed_hub_request, params: params
          expect(flash[:error]).to eq("unable to submit request")
        end
      end

      context 'with uneditable application state' do
        before do
          faa_application.update_attributes!(aasm_state: 'cancelled')
        end

        it 'redirects to applications path with alert message' do
          put :fed_hub_request, params: params
          expect(flash[:alert]).to be_present
          expect(response).to redirect_to(current_applications_insured_sbm_applications_path)
        end
      end

      context 'with missing evidence' do
        let!(:invalid_params) do
          params.merge(id: 'invalid_id')
        end

        it 'handles evidence not found' do
          put :fed_hub_request, params: invalid_params
          expect(flash[:error]).to eq("Evidence not found")
        end
      end

      context 'with missing eligibility' do
        let!(:invalid_params) do
          params.merge(eligibility_id: 'invalid_id')
        end

        it 'handles eligibility not found' do
          put :fed_hub_request, params: invalid_params
          expect(flash[:error]).to eq("Eligibility not found")
        end
      end

      context 'with missing applicant' do
        let!(:invalid_params) do
          params.merge(applicant_id: 'invalid_id')
        end

        it 'handles applicant not found' do
          put :fed_hub_request, params: invalid_params
          expect(flash[:error]).to eq("Applicant not found")
        end
      end

      context 'with missing application' do
        let!(:invalid_params) do
          params.merge(application_gid: 'invalid_gid')
        end

        it 'handles application not found' do
          put :fed_hub_request, params: invalid_params
          expect(flash[:error]).to eq("Application not found")
        end
      end
    end
  end

  context 'unauthorized user' do
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      income_evidence
      ssn_evidence
      family.assign_latest_application_gid
      family.save!
      sign_in(fake_user)
    end

    context 'put #update' do
      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          admin_action: 'verify',
          verification_reason: 'Document in EnrollApp'
        }
      end

      it 'returns authorization error' do
        put :update, params: params
        expect(flash[:error]).to include("Access not allowed")
        expect(response).to have_http_status(:found)
      end
    end

    context 'put #extend_due_date' do
      let!(:extend_params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          extension_period: 30
        }
      end

      it 'returns authorization error' do
        put :extend_due_date, params: extend_params
        expect(flash[:error]).to include("Access not allowed")
        expect(response).to have_http_status(:found)
      end
    end
  end

  context 'IVL eligibility with SSN evidence' do
    before do
      sign_in(admin_user)
    end

    let!(:ivl_params) do
      {
        eligibility_id: ivl_eligibility.id,
        id: ssn_evidence.id,
        application_gid: faa_application&.to_global_id&.uri&.to_s,
        applicant_id: applicant&.id,
        person_id: primary_applicant.person.id,
        eligibility_kind: 'individual_market_eligibility',
        evidence_key: :social_security_number_evidence,
        admin_action: 'verify',
        verification_reason: 'Document in EnrollApp'
      }
    end

    context 'with valid IVL verification reason' do
      it 'updates IVL evidence with valid reason' do
        put :update, params: ivl_params
        expect(flash[:success]).to eq("Social security number evidence successfully verified.")
      end
    end

    context 'extend_due_date for SSN evidence' do
      let!(:ivl_extend_params) do
        {
          eligibility_id: ivl_eligibility.id,
          id: ssn_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'individual_market_eligibility',
          evidence_key: :social_security_number_evidence,
          extension_period: 45
        }
      end

      before do
        allow(ssn_evidence).to receive(:extend_due_date).and_return(true)
      end

      it 'extends SSN evidence due date' do
        put :extend_due_date, params: ivl_extend_params
        expect(flash[:success]).to include("due date extended")
      end
    end
  end
end
