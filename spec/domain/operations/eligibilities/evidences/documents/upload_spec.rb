# frozen_string_literal: true

RSpec.describe Operations::Eligibilities::Evidences::Documents::Upload, type: :operation do
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_applicant }

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

  let(:aptc_csr_eligibility) { FactoryBot.create(:aptc_csr_eligibility, eligible: applicant) }
  let(:income_evidence) { FactoryBot.create(:income_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }

  let(:file) { fixture_file_upload("#{Rails.root}/test/uhic.jpg") }
  let(:files) { [file] }
  let(:doc_uri) { "urn:openhbx:terms:v1:file_storage:s3:bucket:id-verification#sample-key" }

  let(:operation) { described_class.new }

  let(:error_message_params) do
    {file_types: FileUploadValidator.new(file_data: nil, content_types: FileUploadValidator::VERIFICATION_DOC_TYPES).human_readable_file_types,
     size_in_mb: EnrollRegistry[:upload_file_size_limit_in_mb].item}
  end

  before do
    allow(operation).to receive(:valid_file_uploads?).and_return(true)
    allow(Aws::S3Storage).to receive(:save).and_return(doc_uri)
  end

  describe '#call' do
    context 'with income evidence' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          file: files,
          current_user: user
        }
      end

      context 'with valid parameters and files' do
        it 'successfully uploads files and returns success' do
          result = operation.call(params)

          expect(result).to be_success
          expect(result.success).to be_an(Array)
          expect(result.success.size).to eq(1)
          expect(result.success.first).to be_a(Document)
        end

        it 'creates a document record' do
          expect { operation.call(params) }.to change { income_evidence.documents.count }.by(1)

          document = income_evidence.documents.last
          expect(document.identifier).to eq(doc_uri)
          expect(document.subject).to eq(file.original_filename)
          expect(document.title).to eq(file.original_filename)
          expect(document.status).to eq("downloaded")
        end

        it 'adds verification history' do
          initial_history_count = income_evidence.verification_histories.count
          operation.call(params)

          expect(income_evidence.reload.verification_histories.count).to be > initial_history_count
        end

        it 'updates evidence status when can move to review' do
          allow(income_evidence).to receive(:can_move_to_review?).and_return(true)
          expect(income_evidence).to receive(:move_to_review!)

          operation.call(params)
        end

        it 'updates evidence updated_by field' do
          operation.call(params)
          expect(income_evidence.reload.updated_by).to eq(user.oim_id)
        end
      end

      context 'with multiple files' do
        let(:file2) { fixture_file_upload("#{Rails.root}/test/uhic.jpg") }
        let(:files) { [file, file2] }

        it 'uploads all files successfully' do
          result = operation.call(params)

          expect(result).to be_success
          expect(result.success.size).to eq(2)
          expect(income_evidence.reload.documents.count).to eq(2)
        end
      end
    end

    context 'with ssn evidence' do
      let(:params) do
        {
          application: faa_application,
          evidence: ssn_evidence,
          file: files,
          current_user: user
        }
      end

      it 'successfully uploads files for ssn evidence' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.success.size).to eq(1)
        expect(ssn_evidence.reload.documents.count).to eq(1)
      end
    end

    context 'with invalid parameters' do
      context 'when evidence is blank' do
        let(:params) do
          {
            application: faa_application,
            evidence: nil,
            file: files,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Unable to fetch evidence")
        end
      end

      context 'when file is blank' do
        let(:params) do
          {
            application: faa_application,
            evidence: income_evidence,
            file: nil,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("File not uploaded. Please select the file to upload.")
        end
      end

      context 'when file is empty array' do
        let(:params) do
          {
            application: faa_application,
            evidence: income_evidence,
            file: [],
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("File not uploaded. Please select the file to upload.")
        end
      end
    end

    context 'with invalid file types' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          file: files,
          current_user: user
        }
      end

      before do
        allow(operation).to receive(:valid_file_uploads?).and_return(false)
      end

      it 'returns failure with detailed file type error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to include(l10n(
                                            "upload_doc_error", error_message_params
                                          ))
      end

      it 'calls l10n with correct parameters' do
        expect(operation).to receive(:l10n).with(
          "upload_doc_error",
          hash_including(:size_in_mb)
        )

        operation.call(params)
      end

      it 'returns error message matching expected localized text' do
        allow(operation).to receive(:valid_file_uploads?).and_return(false)

        result = operation.call(params)
        expected_message = l10n(
          "upload_doc_error",
          error_message_params
        )

        expect(result).to be_failure
        expect(result.failure).to eq(expected_message)
      end
    end

    context 'when AWS S3 upload fails' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          file: files,
          current_user: user
        }
      end

      before do
        allow(Aws::S3Storage).to receive(:save).and_return(nil)
      end

      it 'returns failure with storage error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Upload errors: Failed to upload file to storage")
      end
    end

    context 'when AWS S3 raises an exception' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          file: files,
          current_user: user
        }
      end

      before do
        allow(Aws::S3Storage).to receive(:save).and_raise(StandardError.new("S3 connection failed"))
      end

      it 'returns failure with exception message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Upload errors: Storage upload failed: S3 connection failed")
      end
    end

    context 'when evidence save fails during history update' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          file: files,
          current_user: user
        }
      end

      before do
        allow(faa_application).to receive(:save).and_return(false)
      end

      it 'returns failure with history error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to match(/Application save failed/)
      end
    end

    context 'with user having oim_id' do
      let(:user_with_oim_id) { FactoryBot.create(:user, person: person, oim_id: "test_oim_123") }
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          file: files,
          current_user: user_with_oim_id
        }
      end

      it 'uses user oim_id in history and evidence update' do
        operation.call(params)

        expect(income_evidence.reload.updated_by).to eq(user_with_oim_id.oim_id)
      end
    end

    context 'when evidence cannot move to review' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          file: files,
          current_user: user
        }
      end

      before do
        allow(income_evidence).to receive(:can_move_to_review?).and_return(false)
      end

      it 'does not call move_to_review!' do
        expect(income_evidence).not_to receive(:move_to_review!)
        operation.call(params)
      end

      it 'still completes successfully' do
        result = operation.call(params)
        expect(result).to be_success
      end
    end
  end
end
