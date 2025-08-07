# frozen_string_literal: true

RSpec.describe Eligibilities::Evidences::DocumentsController, type: :controller do
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

  let!(:fake_person) { FactoryBot.create(:person, :with_consumer_role) }
  let!(:fake_user) {FactoryBot.create(:user, :person => fake_person)}
  let!(:fake_family) { FactoryBot.create(:family, :with_primary_family_member, person: fake_person) }
  let!(:fake_family_member) { fake_family.family_members.first }

  let!(:admin_person) { FactoryBot.create(:person, :with_hbx_staff_role) }
  let!(:admin_user) {FactoryBot.create(:user, :with_hbx_staff_role, :person => admin_person)}
  let!(:permission) { FactoryBot.create(:permission, :super_admin) }
  let!(:update_admin) { admin_person.hbx_staff_role.update_attributes(permission_id: permission.id) }

  let(:aptc_csr_eligibility)  { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories,  :outstanding, eligibility: aptc_csr_eligibility) }
  let(:determination) { ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family) }
  let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }

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
    FactoryBot.create(
      :financial_assistance_applicant,
      family_member_id: primary_applicant.id,
      person_hbx_id: person.hbx_id,
      application: faa_application
    )
  end

  let(:file) { [fixture_file_upload("#{Rails.root}/test/uhic.jpg")] }

  context 'admin' do
    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
      income_evidence
      ssn_evidence
      family.assign_latest_application_gid
      family.save!
      sign_in(admin_user)
    end

    context 'POST #upload' do
      let(:bucket_name) { 'id-verification' }
      let(:doc_id) { "urn:openhbx:terms:v1:file_storage:s3:bucket:#{bucket_name}sample-key" }

      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          evidence_id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          family: family.id,
          file: file
        }
      end

      context 'with valid params' do
        before do
          allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_new_verifications_household_summary).and_return(true)
          allow(Aws::S3Storage).to receive(:save).and_return(doc_id)
        end

        it 'uploads a new document for an evidence' do
          post :upload, params: params
          expect(flash[:success]).to eq("Document successfully Submitted")
        end
      end

      context 'with invalid params' do
        before do
          allow(Aws::S3Storage).to receive(:save).and_return(nil)
        end

        let!(:params) do
          {
            eligibility_id: aptc_csr_eligibility.id,
            evidence_id: income_evidence.id,
            application_gid: faa_application&.to_global_id&.uri&.to_s,
            applicant_id: applicant&.id,
            person_id: primary_applicant.person.id,
            eligibility_kind: 'aptc_csr_eligibility',
            evidence_key: :income_evidence,
            family: family.id
          }
        end

        it 'display error message if no file is sent' do
          post :upload, params: params
          expect(flash[:error]).to eq("File not uploaded. Please select the file to upload.")
        end
      end
    end

    context 'GET #download' do
      context 'with valid params' do

        before do
          allow(controller).to receive(:get_document).with('sample-key').and_return(Document.new)
        end

        let!(:params) do
          {
            eligibility_id: aptc_csr_eligibility.id,
            evidence_id: income_evidence.id,
            application_gid: faa_application&.to_global_id&.uri&.to_s,
            applicant_id: applicant&.id,
            person_id: primary_applicant.person.id,
            key: "sample-key"
          }
        end

        it 'downloads the requested document' do
          get :download, params: params
          expect(response).to be_successful
        end
      end
    end

    context 'DELETE #destroy' do
      let(:bucket_name) { 'id-verification' }
      let!(:document) do
        income_evidence.documents.create!(identifier: "test#sample-key",
                                          title: "sample-document.pdf", subject: "sample-document.pdf")
      end
      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          evidence_id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          doc_key: "sample-key"
        }
      end

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_new_verifications_household_summary).and_return(true)
      end

      it 'destroys the requested document' do
        expect(income_evidence.documents.count).to eq 1
        delete :destroy, params: params
        expect(income_evidence.reload.documents.count).to eq 0
      end

      it 'redirects with success message' do
        delete :destroy, params: params
        expect(flash[:danger]).to be_present
        expect(response).to redirect_to(verification_detail_insured_families_path(
                                          person_id: params[:person_id],
                                          eligibility_kind: params[:eligibility_kind],
                                          evidence_key: params[:evidence_key]
                                        ))
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

    context 'POST #upload' do
      let(:bucket_name) { 'id-verification' }
      let(:doc_id) { "urn:openhbx:terms:v1:file_storage:s3:bucket:#{bucket_name}sample-key" }
      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          evidence_id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          family: family.id,
          file: file
        }
      end

      context 'with unauthorized user' do
        before do
          allow(Aws::S3Storage).to receive(:save).and_return(doc_id)
        end

        it 'returns failure' do
          post :upload, params: params
          expect(flash[:error]).to eq("Access not allowed for financial_assistance/evidences/income_evidence_policy.upload?, (Pundit policy)")
        end
      end
    end

    context 'GET #download' do
      context 'with unauthorized user' do
        before do
          allow(controller).to receive(:get_document).with('sample-key').and_return(Document.new)
        end

        let!(:params) do
          {
            eligibility_id: aptc_csr_eligibility.id,
            evidence_id: income_evidence.id,
            application_gid: faa_application&.to_global_id&.uri&.to_s,
            applicant_id: applicant&.id,
            person_id: primary_applicant.person.id,
            key: "sample-key"
          }
        end

        it 'should not download the requested document' do
          get :download, params: params
          expect(response).to have_http_status(:found)
          expect(flash[:error]).to eq("Access not allowed for financial_assistance/evidences/income_evidence_policy.download?, (Pundit policy)")
        end
      end
    end

    context 'DELETE #destroy' do
      let(:bucket_name) { 'id-verification' }
      let!(:document) do
        income_evidence.documents.create!(identifier: "test#sample-key",
                                          title: "sample-document.pdf", subject: "sample-document.pdf")
      end
      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          evidence_id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          doc_key: "sample-key"
        }
      end

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:show_new_verifications_household_summary).and_return(true)
      end

      it 'should not destroy the requested document' do
        expect(income_evidence.documents.count).to eq 1
        delete :destroy, params: params
        expect(income_evidence.reload.documents.count).to eq 1
      end
    end
  end
end
