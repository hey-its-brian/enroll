# frozen_string_literal: true

RSpec.describe Operations::Eligibilities::Evidences::History, type: :operation do
  let(:user) { FactoryBot.create(:user, person: person) }
  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:primary_applicant) { family.primary_family_member }

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
  let(:aptc_ssn_evidence) { FactoryBot.create(:social_security_number_evidence, :with_verification_histories, :outstanding, eligibility: aptc_csr_eligibility) }

  let(:operation) { described_class.new }

  describe '#call' do
    context 'with valid parameters' do
      let(:params) do
        {
          application: faa_application,
          applicant: applicant,
          evidence: income_evidence
        }
      end

      it 'successfully retrieves history and returns success' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.success).to be_an(Array)
        expect(result.success).to all(be_an(EvidenceHistoryDecorator))
      end

      it 'sorts history items by date_of_action in descending order' do
        result = operation.call(params)

        expect(result).to be_success
        if result.success.size > 1
          dates = result.success.map(&:date_of_action)
          expect(dates).to eq(dates.sort.reverse)
        end
      end
    end

    context 'with both verification histories and request results' do
      let(:params) do
        {
          application: faa_application,
          applicant: applicant,
          evidence: income_evidence
        }
      end

      before do
        # Add verification histories
        3.times do |i|
          income_evidence.verification_histories.create!(
            action: "verification_history_#{i}",
            update_reason: "test reason #{i}",
            updated_by: user.id
          )
        end
      end

      it 'combines and sorts both types of history records' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.success.size).to eq(5)

        dates = result.success.map(&:date_of_action)
        expect(dates).to eq(dates.sort.reverse)
      end
    end

    context 'with invalid parameters' do
      context 'when application is blank' do
        let(:params) do
          {
            application: nil,
            applicant: applicant,
            evidence: income_evidence
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Application not found")
        end
      end

      context 'when applicant is blank' do
        let(:params) do
          {
            application: faa_application,
            applicant: nil,
            evidence: income_evidence
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Applicant not found")
        end
      end

      context 'when evidence is blank' do
        let(:params) do
          {
            application: faa_application,
            applicant: applicant,
            evidence: nil
          }
        end

        it 'returns failure with error message' do
          result = operation.call(params)

          expect(result).to be_failure
          expect(result.failure).to eq("Evidence not found")
        end
      end
    end

    context 'when evidence has no histories' do
      let(:evidence_without_history) do
        FactoryBot.create(:income_evidence, :outstanding, eligibility: aptc_csr_eligibility)
      end

      let(:params) do
        {
          application: faa_application,
          applicant: applicant,
          evidence: evidence_without_history
        }
      end

      it 'returns success with empty array' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.success).to be_empty
      end
    end

    context 'with evidence decorator functionality' do
      let(:params) do
        {
          application: faa_application,
          applicant: applicant,
          evidence: income_evidence
        }
      end

      before do
        income_evidence.verification_histories.create!(
          action: "verification_submitted",
          update_reason: "User uploaded document",
          updated_by: user.id
        )
      end

      it 'decorates history items with EvidenceHistoryDecorator' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.success.first).to be_an(EvidenceHistoryDecorator)
        expect(result.success.first).to respond_to(:date_of_action)
      end
    end
  end
end
