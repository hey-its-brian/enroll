# frozen_string_literal: true

RSpec.describe Operations::Eligibilities::Evidences::Documents::Delete, type: :operation do
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

  let(:document) do
    income_evidence.documents.create!(
      identifier: "urn:openhbx:terms:v1:file_storage:s3:bucket:id-verification#sample-key",
      title: "test-document.pdf",
      subject: "test-document.pdf",
      status: "downloaded"
    )
  end

  let(:operation) { described_class.new }

  describe '#call' do
    context 'with income evidence' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          key: "sample-key",
          current_user: user
        }
      end

      before { document }

      context 'with valid parameters' do
        it 'successfully deletes document and returns success' do
          result = operation.call(params)

          expect(result).to be_success
          expect(result.success).to be_a(Hash)
          expect(result.success[:message]).to eq("All documents were deleted. Action needed")
          expect(result.success[:type]).to eq(:danger)
        end

        it 'removes the document from evidence' do
          expect { operation.call(params) }.to change { income_evidence.documents.count }.by(-1)
        end

        it 'adds verification history' do
          initial_history_count = income_evidence.verification_histories.count
          operation.call(params)

          expect(income_evidence.reload.verification_histories.count).to be > initial_history_count
        end

        it 'does not mark evidence as rejected when other documents exist' do
          income_evidence.documents.create!(
            identifier: "urn:openhbx:terms:v1:file_storage:s3:bucket:id-verification#another-key",
            title: "another-document.pdf",
            subject: "another-document.pdf",
            status: "downloaded"
          )

          expect(income_evidence).not_to receive(:mark_as_rejected)
          operation.call(params)
        end
      end

      context 'when deleting the last document' do
        it 'marks evidence as rejected and returns danger message' do
          expect(income_evidence).to receive(:mark_as_rejected)
          allow(income_evidence).to receive(:update!).with(updated_by: user.oim_id)

          result = operation.call(params)

          expect(result).to be_success
          expect(result.success[:message]).to eq("All documents were deleted. Action needed")
          expect(result.success[:type]).to eq(:danger)
        end
      end
    end

    context 'with ssn evidence' do
      let(:ssn_document) do
        ssn_evidence.documents.create!(
          identifier: "urn:openhbx:terms:v1:file_storage:s3:bucket:id-verification#ssn-key",
          title: "ssn-document.pdf",
          subject: "ssn-document.pdf",
          status: "downloaded"
        )
      end

      let(:params) do
        {
          application: faa_application,
          evidence: ssn_evidence,
          key: "ssn-key",
          current_user: user
        }
      end

      before { ssn_document }

      it 'successfully deletes document for ssn evidence' do
        result = operation.call(params)

        expect(result).to be_success
        expect(ssn_evidence.reload.documents.count).to eq(0)
      end
    end

    context 'with invalid parameters' do
      context 'when evidence is blank' do
        let(:params) do
          {
            application: faa_application,
            evidence: nil,
            key: "sample-key",
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Unable to fetch evidence")
        end
      end

      context 'when key is blank' do
        let(:params) do
          {
            application: faa_application,
            evidence: income_evidence,
            key: nil,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Document key is required")
        end
      end

      context 'when current_user is blank' do
        let(:params) do
          {
            application: faa_application,
            evidence: income_evidence,
            key: "sample-key",
            current_user: nil
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Current user is required")
        end
      end
    end

    context 'when evidence is verified' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          key: "sample-key",
          current_user: user
        }
      end

      before do
        document
        income_evidence.update!(current_state: :verified)
      end

      it 'returns failure with verification error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Document cannot be deleted because type is verified")
      end
    end

    context 'when document deletion fails' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          key: "sample-key",
          current_user: user
        }
      end

      before do
        document
        allow(document).to receive(:delete)
        allow(document).to receive(:destroyed?).and_return(false)
      end

      it 'returns failure with deletion error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Failed to delete document")
      end
    end

    context 'when verification history save fails' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          key: "sample-key",
          current_user: user
        }
      end

      before do
        document
        allow(faa_application).to receive(:save!).and_raise(StandardError.new("Save failed"))
      end

      it 'returns failure with history error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Application save failed: Save failed")
      end
    end

    context 'when evidence update fails after deleting all documents' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          key: "sample-key",
          current_user: user
        }
      end

      before do
        document
        allow(income_evidence).to receive(:mark_as_rejected).and_raise(StandardError.new("Update failed"))
      end

      it 'returns failure with update error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Failed to update evidence after deleting all documents: Update failed")
      end
    end

    context 'when verification history raises exception' do
      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          key: "sample-key",
          current_user: user
        }
      end

      before do
        document
        allow(income_evidence).to receive(:build_verification_history).and_raise(StandardError.new("History failed"))
      end

      it 'returns failure with history exception message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Verification history failed: History failed")
      end
    end

    context 'with different document key formats' do
      let(:document_with_different_key) do
        income_evidence.documents.create!(
          identifier: "test#different-key-format",
          title: "test-document-2.pdf",
          subject: "test-document-2.pdf",
          status: "downloaded"
        )
      end

      let(:params) do
        {
          application: faa_application,
          evidence: income_evidence,
          key: "different-key-format",
          current_user: user
        }
      end

      before { document_with_different_key }

      it 'finds and deletes document with different identifier format' do
        result = operation.call(params)

        expect(result).to be_success
        expect(income_evidence.reload.documents.count).to eq(0)
      end
    end
  end
end
