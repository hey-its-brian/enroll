# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Operations::Evidences::Income::CallHub, dbclean: :after_each do
  let(:operation) { described_class.new }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member_and_dependent) }
  let(:person) do
    p = family.primary_person
    p.update_attributes(ssn: '123-45-6788')
    p
  end
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }

  let(:applicant) do
    FactoryBot.create(:applicant,
                      application: application,
                      dob: TimeKeeper.date_of_record - 40.years,
                      is_primary_applicant: true,
                      family_member_id: family.family_members[0].id,
                      person_hbx_id: person.hbx_id,
                      first_name: person.first_name,
                      last_name: person.last_name,
                      gender: person.gender,
                      ssn: person.ssn,
                      addresses: [FactoryBot.build(:financial_assistance_address)])
  end

  let(:aptc_csr_eligibility)  do
    eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant, current_state: :initial)
    eligibility.save!
    eligibility
  end

  let(:income_evidence) do
    FactoryBot.create(:income_evidence,
                      eligibility: aptc_csr_eligibility,
                      _type: 'FinancialAssistance::Evidences::IncomeEvidence',
                      key: :income_evidence)
  end


  let(:action_name) { 'hub_request' }
  let(:update_reason) { 'Requesting determination' }
  let(:updated_by) { 'admin@user.com' }

  let(:hbx_profile) { FactoryBot.create(:hbx_profile) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }

  before do
    allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_and_record_publish_application_errors).and_return(true)

    allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
    allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
    allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:valid_params) do
        {
          evidence: income_evidence,
          action_name: action_name,
          update_reason: update_reason,
          updated_by: updated_by
        }
      end

      context 'when evidence has APTC/CSR eligibility type' do
        context 'when hub call succeeds' do
          it 'returns success' do
            result = operation.call(valid_params)
            expect(result).to be_success
            expect(result.value!).to eq("Event published successfully")
            income_evidence.reload
            expect(income_evidence.verification_histories.count).to eq(1)
            expect(income_evidence.current_state).to be(:pending)
            expect(aptc_csr_eligibility.current_state).to be(:verification_in_progress)
            expect(aptc_csr_eligibility.is_satisfied).to be false
            expect(aptc_csr_eligibility.state_histories.count).to eq(1)
            expect(aptc_csr_eligibility.state_histories.last.to_state).to eq(:verification_in_progress)
            expect(aptc_csr_eligibility.state_histories.last.from_state).to eq(:initial)
          end
        end
      end

      context 'when hub call fails' do
        before do
          person.update_attributes!(ssn: nil)
          applicant.update_attributes!(ssn: nil)
        end

        context 'for income evidence' do
          let(:mock_enrollments) { double('enrollments') }

          context 'when applicant is enrolled in APTC/CSR enrollment' do
            before do
              allow(applicant).to receive(:enrolled_in_any_aptc_csr_enrollments?).and_return(true)
            end

            it 'determines income evidence current state' do
              result = operation.call(valid_params)
              expect(result).to be_failure
              income_evidence.reload
              expect(income_evidence.verification_histories.count).to eq(2)
              expect(income_evidence.verification_histories.last.action).to eq('hub_request_failed')
              expect(income_evidence.verification_histories.last.update_reason).to eq("Applicant validity: Income Evidence verification request failed due to [\"No SSN for applicant\"]")
              expect(income_evidence.current_state).to be(:outstanding)
              expect(aptc_csr_eligibility.current_state).to be(:verification_in_progress)
              expect(aptc_csr_eligibility.is_satisfied).to be false
              expect(aptc_csr_eligibility.state_histories.count).to eq(1)
              expect(aptc_csr_eligibility.state_histories.last.to_state).to eq(:verification_in_progress)
              expect(aptc_csr_eligibility.state_histories.last.from_state).to eq(:initial)
            end
          end

          context 'when applicant is not enrolled in APTC/CSR enrollment' do
            before do
              allow(income_evidence).to receive(:fetch_enrolled_enrollments).and_return(mock_enrollments)
              allow(applicant).to receive(:enrolled_in_any_aptc_csr_enrollments?).and_return(false)
            end

            it 'determines income evidence current state' do
              result = operation.call(valid_params)
              expect(result).to be_failure
              income_evidence.reload
              expect(income_evidence.verification_histories.count).to eq(2)
              expect(income_evidence.verification_histories.last.action).to eq('hub_request_failed')
              expect(income_evidence.verification_histories.last.update_reason).to eq("Applicant validity: Income Evidence verification request failed due to [\"No SSN for applicant\"]")
              expect(income_evidence.current_state).to be(:negative_response_received)
            end
          end
        end
      end
    end

    context 'with invalid parameters' do
      context 'when evidence is missing' do
        let(:params_without_evidence) do
          {
            action_name: action_name,
            update_reason: update_reason,
            updated_by: updated_by
          }
        end

        it 'returns failure' do
          result = operation.call(params_without_evidence)
          expect(result).to be_failure
          expect(result.failure).to eq("Missing required params: evidence")
        end
      end

      context 'when action_name is missing' do
        let(:params_without_action) do
          {
            evidence: income_evidence,
            update_reason: update_reason,
            updated_by: updated_by
          }
        end

        it 'returns failure' do
          result = operation.call(params_without_action)
          expect(result).to be_failure
          expect(result.failure).to eq("Missing required params: action_name")
        end
      end

      context 'when update_reason is missing' do
        let(:params_without_reason) do
          {
            evidence: income_evidence,
            action_name: action_name,
            updated_by: updated_by
          }
        end

        it 'returns failure' do
          result = operation.call(params_without_reason)
          expect(result).to be_failure
          expect(result.failure).to eq("Missing required params: update_reason")
        end
      end

      context 'when updated_by is missing' do
        let(:params_without_updated_by) do
          {
            evidence: income_evidence,
            action_name: action_name,
            update_reason: update_reason
          }
        end

        it 'returns failure' do
          result = operation.call(params_without_updated_by)
          expect(result).to be_failure
          expect(result.failure).to eq("Missing required params: updated_by")
        end
      end
    end
  end

  describe 'private methods' do
    describe '#record_history' do
      let(:evidence) { income_evidence }
      let(:action) { 'test_action' }
      let(:reason) { 'test_reason' }
      let(:user) { 'test_user' }
      let(:mock_histories) { double('verification_histories') }

      before do
        allow(evidence).to receive(:verification_histories).and_return(mock_histories)
      end

      it 'builds verification history with correct attributes' do
        expect(mock_histories).to receive(:build).with(
          action: action,
          update_reason: reason,
          updated_by: user
        )
        operation.send(:record_history, evidence, action, reason, user)
      end
    end
  end
end