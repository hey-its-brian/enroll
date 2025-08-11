# frozen_string_literal: true

RSpec.describe Operations::Eligibilities::Evidences::ExtendDueDate, type: :operation do
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

  let(:operation) { described_class.new }

  before do
    allow(TimeKeeper).to receive(:date_of_record).and_return(Date.current)
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:verification_due_on_options).and_return(false)
  end

  describe '#call' do
    context 'with income evidence' do
      context 'extending to specific date' do
        let(:specific_date) { (Date.current + 45.days).strftime('%Y-%m-%d') }
        let(:params) do
          {
            evidence: income_evidence,
            application: faa_application,
            current_user: user,
            due_on: specific_date
          }
        end

        before do
          allow(income_evidence).to receive(:extend_due_date).and_return(true)
        end

        it 'successfully extends due date to specific date' do
          result = operation.call(params)

          expect(result).to be_success
          expect(result.success).to include("Income Evidence due date extended")
        end

        it 'calls extend_due_date with correct parameters' do
          expect(income_evidence).to receive(:extend_due_date).with(
            'extend_due_date',
            Date.parse(specific_date),
            user.oim_id,
            kind_of(String)
          )

          operation.call(params)
        end

        it 'saves the application' do
          expect(faa_application).to receive(:save!).and_return(true)
          operation.call(params)
        end
      end

      context 'extending by period' do
        let(:params) do
          {
            evidence: income_evidence,
            application: faa_application,
            current_user: user,
            extension_period: 60
          }
        end

        before do
          allow(income_evidence).to receive(:extend_due_date).and_return(true)
        end

        it 'successfully extends due date by period' do
          result = operation.call(params)

          expect(result).to be_success
          expect(result.success).to include("Income Evidence due date extended")
        end

        it 'uses provided extension period' do
          expected_due_date = Date.current + 60.days

          expect(income_evidence).to receive(:extend_due_date).with(
            'extend_due_date',
            expected_due_date,
            user.oim_id,
            kind_of(String)
          )

          operation.call(params)
        end
      end
    end

    context 'with SSN evidence' do
      let(:params) do
        {
          evidence: ssn_evidence,
          application: faa_application,
          current_user: user,
          extension_period: 45
        }
      end

      before do
        allow(ssn_evidence).to receive(:extend_due_date).and_return(true)
      end

      it 'successfully extends SSN evidence due date' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.success).to include("Social Security Number Evidence due date extended")
      end
    end

    context 'with verification_due_on_options feature enabled' do
      let(:params) do
        {
          evidence: income_evidence,
          application: faa_application,
          current_user: user,
          extension_period: 30
        }
      end

      before do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:verification_due_on_options).and_return(true)
        allow(income_evidence).to receive(:extend_due_date).and_return(true)
        allow(I18n).to receive(:t).and_call_original
      end

      it 'uses feature-specific localization' do
        expect(I18n).to receive(:t).with(
          'admin.verifications.extend.history_description.static',
          hash_including(:day_offset, :date)
        ).and_return("Extended due date")

        operation.call(params)
      end
    end

    context 'with invalid parameters' do
      context 'when evidence is blank' do
        let(:params) do
          {
            evidence: nil,
            application: faa_application,
            current_user: user,
            extension_period: 30
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Evidence is required")
        end
      end

      context 'when application is blank' do
        let(:params) do
          {
            evidence: income_evidence,
            application: nil,
            current_user: user,
            extension_period: 30
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Application is required")
        end
      end

      context 'when current_user is blank' do
        let(:params) do
          {
            evidence: income_evidence,
            application: faa_application,
            current_user: nil,
            extension_period: 30
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Current user is required")
        end
      end

      context 'when both due_on and extension_period are blank' do
        let(:params) do
          {
            evidence: income_evidence,
            application: faa_application,
            current_user: user
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Due on is required")
        end
      end
    end

    context 'with invalid evidence state' do
      let(:verified_evidence) { FactoryBot.create(:income_evidence, :verified, eligibility: aptc_csr_eligibility) }
      let(:params) do
        {
          evidence: verified_evidence,
          application: faa_application,
          current_user: user,
          extension_period: 30
        }
      end

      it 'returns failure when evidence is not in outstanding state' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Evidence must be in outstanding state")
      end
    end

    context 'when evidence has no due date' do
      let(:evidence_without_due_date) { FactoryBot.create(:income_evidence, :outstanding, eligibility: aptc_csr_eligibility, due_on: nil) }
      let(:params) do
        {
          evidence: evidence_without_due_date,
          application: faa_application,
          current_user: user,
          extension_period: 30
        }
      end

      it 'returns failure when evidence has no due date' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Evidence must have a due date")
      end
    end

    context 'when extend_due_date method fails' do
      let(:params) do
        {
          evidence: income_evidence,
          application: faa_application,
          current_user: user,
          extension_period: 30
        }
      end

      before do
        allow(income_evidence).to receive(:extend_due_date).and_raise(StandardError.new("Extension failed"))
      end

      it 'returns failure with error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Unable to extend due date")
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with(/Error extending by period/)
        operation.call(params)
      end
    end

    context 'when application save fails' do
      let(:params) do
        {
          evidence: income_evidence,
          application: faa_application,
          current_user: user,
          extension_period: 30
        }
      end

      before do
        allow(income_evidence).to receive(:extend_due_date).and_return(true)
        allow(faa_application).to receive(:save!).and_raise(StandardError.new("Save failed"))
      end

      it 'returns failure with save error message' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq("Application save failed: Save failed")
      end

      it 'logs the save error' do
        expect(Rails.logger).to receive(:error).with(/Application save failed/)
        operation.call(params)
      end
    end

    context 'when date parsing fails' do
      let(:params) do
        {
          evidence: income_evidence,
          application: faa_application,
          current_user: user,
          due_on: "invalid-date"
        }
      end

      it 'returns failure with parsing error' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to include("Unable to extend due date")
      end
    end

    context 'when I18n translation fails' do
      let(:params) do
        {
          evidence: income_evidence,
          application: faa_application,
          current_user: user,
          extension_period: 30
        }
      end

      before do
        allow(income_evidence).to receive(:extend_due_date).and_return(true)
        allow(I18n).to receive(:t).and_raise(StandardError.new("Translation failed"))
      end

      it 'falls back to default message format' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.success).to include("Income Evidence due date extended")
      end
    end
  end
end
