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

    context 'GET #index' do
      context 'with valid params' do
        before do
          ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
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
            family_id: faa_application.family&.id
          }
        end

        it 'returns success response' do
          get :index, params: params

          expect(response).to be_successful
        end

        it 'sets expected instance variables from the operation result' do
          get :index, params: params

          expect(assigns(:uploads)).to be_present
          expect(assigns(:years)).to eq([faa_application.assistance_year])
        end

        it 'renders the index template' do
          get :index, params: params

          expect(response).to render_template(:index)
        end

        context 'when most recent application year is different from current year' do
          let(:newer_application) do
            FactoryBot.create(
              :financial_assistance_application,
              family_id: family.id,
              aasm_state: 'determined',
              submitted_at: Time.now + 1.year,
              assistance_year: TimeKeeper.date_of_record.year + 1
            )
          end

          let(:newer_applicant) do
            FactoryBot.create(
              :financial_assistance_applicant,
              family_member_id: primary_applicant.id,
              person_hbx_id: person.hbx_id,
              application: newer_application
            )
          end

          let(:newer_aptc_csr_eligibility)  { FactoryBot.create(:aptc_csr_eligibility, eligible: newer_applicant) }
          let(:newer_income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories,  :outstanding, eligibility: newer_aptc_csr_eligibility) }
          let(:newer_determination) { ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family) }

          let!(:newer_params) do
            {
              eligibility_id: newer_aptc_csr_eligibility.id,
              evidence_id: newer_income_evidence.id,
              application_gid: newer_application&.to_global_id&.uri&.to_s,
              applicant_id: newer_applicant&.id,
              person_id: person.id,
              eligibility_kind: 'aptc_csr_eligibility',
              evidence_key: :income_evidence,
              family_id: newer_application.family&.id
            }
          end

          before do
            ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
            newer_income_evidence.documents.create!(identifier: "test#sample-key",
                                                    title: "sample-document.pdf", subject: "sample-document.pdf")
            newer_income_evidence.reload
          end

          it 'returns success response' do
            get :index, params: newer_params

            expect(response).to be_successful
          end

          it 'sets expected instance variables from the operation result' do
            get :index, params: newer_params

            expect(assigns(:uploads)).to be_present
            expect(assigns(:years)).to eq([newer_application.assistance_year, faa_application.assistance_year])
          end

          it 'renders the index template' do
            get :index, params: newer_params

            expect(response).to render_template(:index)
          end

          it 'will filter by most determined application assistance_year if no year parameter is provided' do
            get :index, params: newer_params

            expect(assigns(:uploads)).to eq(newer_income_evidence.documents)
          end
        end
      end

      context 'with failed operation' do
        before do
          request.headers["Accept"] = "text/html"
          request.headers["X-Requested-With"] = "XMLHttpRequest"
          ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
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
            evidence_key: :income_evidence
          }
        end

        it 'sets flash error' do
          get :index, params: params
          expect(flash[:error]).to eq("Family ID is required")
        end
      end

      context 'with AJAX request' do
        before do
          request.headers["Accept"] = "text/html"
          request.headers["X-Requested-With"] = "XMLHttpRequest"
          ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
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
            family_id: faa_application.family&.id
          }
        end

        it 'renders the table partial' do
          get :index, params: params, xhr: true
          expect(response).to render_template(partial: '_table')
        end
      end
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
        expect(response).to redirect_to(eligibility_evidence_path(
                                          eligibility_id: aptc_csr_eligibility.id,
                                          id: income_evidence.id,
                                          application_gid: params[:application_gid],
                                          applicant_id: params[:applicant_id],
                                          person_id: params[:person_id],
                                          eligibility_kind: params[:eligibility_kind],
                                          evidence_key: params[:evidence_key],
                                          family_id: family.id
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

    context 'GET #index' do
      let!(:params) do
        {
          eligibility_id: aptc_csr_eligibility.id,
          evidence_id: income_evidence.id,
          application_gid: faa_application&.to_global_id&.uri&.to_s,
          applicant_id: applicant&.id,
          person_id: primary_applicant.person.id,
          eligibility_kind: 'aptc_csr_eligibility',
          evidence_key: :income_evidence,
          family_id: faa_application.family&.id
        }
      end

      context 'with unauthorized user' do
        before do
          ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
        end

        it 'returns failure' do
          get :index, params: params
          expect(flash[:error]).to eq("Access not allowed for financial_assistance/evidences/income_evidence_policy.index?, (Pundit policy)")
        end
      end
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
