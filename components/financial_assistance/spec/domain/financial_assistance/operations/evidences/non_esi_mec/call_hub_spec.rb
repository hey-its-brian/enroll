# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Operations::Evidences::NonEsiMec::CallHub, dbclean: :after_each do
  include Dry::Monads[:do, :result]
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
    eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant)
    eligibility.save!
    eligibility
  end

  let!(:non_esi_evidence) do
    FactoryBot.create(:non_esi_mec_evidence, eligibility: aptc_csr_eligibility, _type: 'FinancialAssistance::Evidences::NonEsiMecEvidence', key: :non_esi_mec_evidence, title: 'Non ESI MEC Evidence', description: 'NonEsiMecEvidence',
                                             current_state: "initial")
  end

  let(:action_name) { 'Hub Request' }
  let(:update_reason) { "Requested Hub for verification" }
  let(:updated_by) { 'admin@user.com' }
  let(:hbx_profile) { FactoryBot.create(:hbx_profile) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:benefit_coverage_period) { hbx_profile.benefit_sponsorship.benefit_coverage_periods.first }

  before do
    allow(HbxProfile).to receive(:current_hbx).and_return hbx_profile
    allow(hbx_profile).to receive(:benefit_sponsorship).and_return benefit_sponsorship
    allow(benefit_sponsorship).to receive(:current_benefit_period).and_return(benefit_coverage_period)
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:valid_params) do
        {
          evidence: non_esi_evidence,
          action_name: action_name,
          update_reason: update_reason,
          updated_by: updated_by
        }
      end

      context 'when hub call succeeds' do
        before do
          family.assign_latest_application_gid
          family.save!

          application.applicants.each(&:build_ivl_eligibility_with_evidences)
          application.save!

          family.family_members.each do |fm|
            family.build_consumer_role(fm)
            fm.person.reload
          end
        end

        it 'returns success' do
          result = operation.call(valid_params)
          expect(result).to be_success
          expect(result.value!).to eq("Event published successfully")
          non_esi_evidence.reload
          expect(non_esi_evidence.verification_histories.count).to eq(1)
          expect(non_esi_evidence.verification_histories.last.action).to eq('Hub Request')
          expect(non_esi_evidence.verification_histories.last.update_reason).to eq(update_reason)
          expect(non_esi_evidence.verification_histories.last.updated_by).to eq(updated_by)
          expect(non_esi_evidence.current_state).to be(:pending)
          expect(non_esi_evidence.state_histories.count).to eq(1)
          expect(non_esi_evidence.state_histories.last.to_state).to eq(:pending)
          expect(non_esi_evidence.state_histories.last.from_state).to eq(:initial)
          expect(aptc_csr_eligibility.current_state).to be(:verification_in_progress)
          expect(aptc_csr_eligibility.is_satisfied).to be false
          expect(aptc_csr_eligibility.state_histories.count).to eq(1)
          expect(aptc_csr_eligibility.state_histories.last.to_state).to eq(:verification_in_progress)
          expect(aptc_csr_eligibility.state_histories.last.from_state).to eq(:initial)
        end

        context 'when there are multiple applicants' do
          let(:person2) do
            p = family.dependents.first.person
            p.update_attributes(ssn: '725-73-9934')
            p
          end

          let(:applicant2) do
            FactoryBot.create(:applicant,
                              application: application,
                              dob: TimeKeeper.date_of_record - 40.years,
                              is_primary_applicant: false,
                              family_member_id: family.family_members[1].id,
                              person_hbx_id: person2.hbx_id,
                              first_name: person2.first_name,
                              last_name: person2.last_name,
                              gender: person2.gender,
                              ssn: person2.ssn,
                              addresses: [FactoryBot.build(:financial_assistance_address)])
          end

          let(:aptc_csr_eligibility2)  do
            eligibility = FactoryBot.create(:aptc_csr_eligibility, eligible: applicant2, current_state: :initial)
            eligibility.save!
            eligibility
          end

          let(:non_esi_evidence2) do
            FactoryBot.create(:non_esi_mec_evidence,
                              eligibility: aptc_csr_eligibility2,
                              _type: 'FinancialAssistance::Evidences::NonEsiMecEvidence',
                              key: :non_esi_mec_evidence)
          end

          before do
            applicant2
            aptc_csr_eligibility2
            non_esi_evidence2

            applicant2.build_ivl_eligibility_with_evidences
            application.save!
          end

          it "updates non requesting applicants' evidence state to pending" do
            operation.call(valid_params)
            applicant2.reload
            evidence = applicant2.aptc_csr_eligibility.non_esi_mec_evidence

            expect(evidence.current_state).to be(:pending)
          end

          it 'creates verification history for non-requesting applicant' do
            operation.call(valid_params)
            applicant2.reload
            evidence = applicant2.aptc_csr_eligibility.non_esi_mec_evidence

            expect(evidence.verification_histories.count).to eq(1)
            expect(evidence.verification_histories.last.action).to eq('hub_request')
            expect(evidence.verification_histories.last.update_reason).to eq("Requested Hub for verification, triggered via applicant HBX ID #{applicant.person_hbx_id}")
          end

          it 'updates eligibility state for non-requesting applicant' do
            operation.call(valid_params)
            applicant2.reload
            eligibility = applicant2.aptc_csr_eligibility

            expect(eligibility.current_state).to be(:verification_in_progress)
            expect(eligibility.is_satisfied).to be_falsey
          end

          it 'does not create verification history for non-requesting applicant not applying for coverage' do
            applicant2.update_attributes!(is_applying_coverage: false)
            application.reload

            operation.call(valid_params)
            evidence = applicant2.aptc_csr_eligibility.non_esi_mec_evidence

            expect(evidence.current_state).to be(:initial)
            expect(evidence.verification_histories.count).to eq(0)
          end
        end
      end

      context 'when hub call fails for applicant' do
        before do
          person.update_attributes!(ssn: nil)
          applicant.update_attributes!(ssn: nil)
        end

        it 'should not send the request and record failure' do
          result = operation.call(valid_params)
          expect(result).to be_failure
          non_esi_evidence.reload
          expect(non_esi_evidence.verification_histories.count).to eq(2)
          expect(non_esi_evidence.verification_histories.last.action).to eq('hub_request_failed')
          expect(non_esi_evidence.verification_histories.last.update_reason).to eq("Applicant validity: Non Esi Mec Evidence verification request failed due to [\"No SSN for applicant\"]")
          expect(non_esi_evidence.verification_histories.last.updated_by).to eq("system")
          expect(non_esi_evidence.current_state).to be(:attested)
          expect(non_esi_evidence.state_histories.count).to eq(1)
          expect(non_esi_evidence.state_histories.last.to_state).to eq(:attested)
          expect(non_esi_evidence.state_histories.last.from_state).to eq(:initial)
          expect(aptc_csr_eligibility.current_state).to be(:satisfied)
          expect(aptc_csr_eligibility.is_satisfied).to be true
          expect(aptc_csr_eligibility.state_histories.count).to eq(1)
          expect(aptc_csr_eligibility.state_histories.last.to_state).to eq(:satisfied)
          expect(aptc_csr_eligibility.state_histories.last.from_state).to eq(:initial)
        end
      end

      context 'when hub call fails for application' do
        before do
          allow(operation).to receive(:build_application_payload_entity).and_return(Failure("Invalid application payload"))
          person.update_attributes!(ssn: nil)
          applicant.update_attributes!(ssn: nil)
        end

        it 'should not send the request and record failure' do
          result = operation.call(valid_params)
          expect(result).to be_failure
          non_esi_evidence.reload
          expect(non_esi_evidence.verification_histories.count).to eq(2)
          expect(non_esi_evidence.verification_histories.last.action).to eq('hub_request_failed')
          expect(non_esi_evidence.verification_histories.last.update_reason).to eq("Application validity: Non Esi Mec Evidence verification request failed due to Invalid application payload")
          expect(non_esi_evidence.verification_histories.last.updated_by).to eq("system")
          expect(non_esi_evidence.current_state).to be(:attested)
          expect(non_esi_evidence.state_histories.count).to eq(1)
          expect(non_esi_evidence.state_histories.last.to_state).to eq(:attested)
          expect(non_esi_evidence.state_histories.last.from_state).to eq(:initial)
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
            evidence: non_esi_evidence,
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
            evidence: non_esi_evidence,
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
            evidence: non_esi_evidence,
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
      let(:evidence) { non_esi_evidence }
      let(:due_on) { Date.new(2024, 12, 31) }
      let(:action) { 'test_action' }
      let(:reason) { 'test_reason' }
      let(:user) { 'test_user' }
      let(:mock_histories) { double('verification_histories') }

      before do
        allow(evidence).to receive(:verification_histories).and_return(mock_histories)
        allow(evidence).to receive(:due_on).and_return(due_on)
      end

      it 'builds verification history with correct attributes' do
        expect(mock_histories).to receive(:build).with(
          action: action,
          update_reason: reason,
          updated_by: user,
          due_on: due_on
        )
        operation.send(:record_history, evidence, action, reason, user)
      end
    end
  end
end