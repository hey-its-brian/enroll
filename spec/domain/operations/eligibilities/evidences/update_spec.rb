# frozen_string_literal: true

RSpec.describe Operations::Eligibilities::Evidences::Update, type: :operation do
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
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant, key: :individual_market_eligibility) }
  let(:ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: ivl_eligibility) }

  let(:operation) { described_class.new }

  describe '#call' do
    context 'with income evidence verification' do
      let(:params) do
        {
          evidence: income_evidence,
          admin_action: 'verify',
          update_reason: 'Document in EnrollApp',
          application: faa_application,
          current_user: user
        }
      end

      context 'with valid parameters' do
        it 'successfully verifies evidence' do
          result = operation.call(params)

          expect(result).to be_success
          expect(result.success).to eq("Income evidence successfully verified.")
        end

        it 'marks evidence as verified' do
          operation.call(params)
          expect(income_evidence.reload.current_state).to eq(:verified)
        end

        it 'adds verification history' do
          _initial_history_count = income_evidence.verification_histories.count
          expect(income_evidence).to receive(:build_verification_history).with('verify', 'Document in EnrollApp', user.oim_id)

          operation.call(params)
        end

        it 'saves the application' do
          expect(faa_application).to receive(:save!).and_return(true)
          operation.call(params)
        end

        it 'uses system actor when current_user is nil' do
          params[:current_user] = nil
          expect(income_evidence).to receive(:build_verification_history).with('verify', 'Document in EnrollApp', 'system')

          operation.call(params)
        end
      end

      context 'with return_for_deficiency action' do
        let(:reject_params) do
          params.merge(admin_action: 'return_for_deficiency', update_reason: 'Illegible')
        end

        it 'successfully rejects evidence' do
          result = operation.call(reject_params)

          expect(result).to be_success
          expect(result.success).to eq("Income evidence rejected.")
        end

        it 'marks evidence as rejected' do
          expect(income_evidence).to receive(:mark_as_rejected)
          operation.call(reject_params)
        end

        it 'adds rejection history' do
          expect(income_evidence).to receive(:build_verification_history).with('return_for_deficiency', 'Illegible', user.oim_id)
          operation.call(reject_params)
        end
      end
    end

    context 'with SSN evidence verification' do
      let(:ssn_params) do
        {
          evidence: ssn_evidence,
          admin_action: 'verify',
          update_reason: 'Document in EnrollApp',
          application: faa_application,
          current_user: user
        }
      end

      it 'successfully verifies SSN evidence' do
        result = operation.call(ssn_params)

        expect(result).to be_success
        expect(result.success).to eq("Social security number evidence successfully verified.")
      end

      it 'marks SSN evidence as verified' do
        expect(ssn_evidence).to receive(:mark_as_verified)
        operation.call(ssn_params)
      end
    end

    context 'with invalid parameters' do
      context 'when evidence is blank' do
        let(:invalid_params) do
          {
            evidence: nil,
            admin_action: 'verify',
            update_reason: 'Document in EnrollApp',
            application: faa_application,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Evidence is required")
        end
      end

      context 'when admin_action is blank' do
        let(:invalid_params) do
          {
            evidence: income_evidence,
            admin_action: nil,
            update_reason: 'Document in EnrollApp',
            application: faa_application,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Admin action is required")
        end
      end

      context 'when update_reason is blank' do
        let(:invalid_params) do
          {
            evidence: income_evidence,
            admin_action: 'verify',
            update_reason: nil,
            application: faa_application,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Update reason is required")
        end
      end

      context 'when application is blank' do
        let(:invalid_params) do
          {
            evidence: income_evidence,
            admin_action: 'verify',
            update_reason: 'Document in EnrollApp',
            application: nil,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Application is required")
        end
      end

      context 'when admin_action is invalid' do
        let(:invalid_params) do
          {
            evidence: income_evidence,
            admin_action: 'invalid_action',
            update_reason: 'Document in EnrollApp',
            application: faa_application,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(invalid_params)

          expect(result).to be_failure
          expect(result.failure).to eq("Invalid admin action: invalid_action")
        end
      end
    end

    context 'when evidence verification fails' do
      let(:params) do
        {
          evidence: income_evidence,
          admin_action: 'verify',
          update_reason: 'Document in EnrollApp',
          application: faa_application,
          current_user: user
        }
      end

      before do
        allow(income_evidence).to receive(:mark_as_verified).and_raise(StandardError.new("Verification failed"))
      end

      it 'returns failure with error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Verification action failed: ")
      end
    end

    context 'when evidence rejection fails' do
      let(:params) do
        {
          evidence: income_evidence,
          admin_action: 'return_for_deficiency',
          update_reason: 'Illegible',
          application: faa_application,
          current_user: user
        }
      end

      before do
        allow(income_evidence).to receive(:mark_as_rejected).and_raise(StandardError.new("Rejection failed"))
      end

      it 'returns failure with error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Verification action failed: ")
      end
    end

    context 'when application save fails' do
      let(:params) do
        {
          evidence: income_evidence,
          admin_action: 'verify',
          update_reason: 'Document in EnrollApp',
          application: faa_application,
          current_user: user
        }
      end

      before do
        allow(faa_application).to receive(:save!).and_raise(StandardError.new("Database error"))
      end

      it 'returns failure with error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Application save failed: Database error")
      end
    end

    context 'when process_verification_action fails' do
      let(:params) do
        {
          evidence: income_evidence,
          admin_action: 'verify',
          update_reason: 'Document in EnrollApp',
          application: faa_application,
          current_user: user
        }
      end

      before do
        allow(income_evidence).to receive(:build_verification_history).and_raise(StandardError.new("History update failed"))
      end

      it 'returns failure with error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Verification action failed: ")
      end
    end

    context 'with user without oim_id' do
      let(:user_without_oim_id) { FactoryBot.create(:user, person: person) }
      let(:params) do
        {
          evidence: income_evidence,
          admin_action: 'verify',
          update_reason: 'Document in EnrollApp',
          application: faa_application,
          current_user: user_without_oim_id
        }
      end

      it 'uses user oim_id even when nil' do
        expect(income_evidence).to receive(:build_verification_history).with('verify', 'Document in EnrollApp', user_without_oim_id.oim_id)
        operation.call(params)
      end
    end
  end
end
