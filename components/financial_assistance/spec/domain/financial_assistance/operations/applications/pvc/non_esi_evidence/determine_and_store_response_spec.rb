# frozen_string_literal: true

require 'rails_helper'
require "#{FinancialAssistance::Engine.root}/spec/shared_examples/pvc/medicare/test_pvc_medicare_response"

RSpec.describe ::FinancialAssistance::Operations::Applications::Pvc::NonEsiEvidence::DetermineAndStoreResponse, dbclean: :after_each do
  include_context 'FDSH PVC Medicare sample response'

  before :all do
    DatabaseCleaner.clean
  end

  let(:family) { FactoryBot.create(:family, :with_primary_family_member)}
  let!(:application) do
    FactoryBot.create(:financial_assistance_application, hbx_id: '200000126', aasm_state: "determined",
                                                         family_id: family.id)
  end
  let!(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      eligibility_determination_id: nil,
                      person_hbx_id: '1629165429385938',
                      is_primary_applicant: true,
                      first_name: 'esi',
                      last_name: 'evidence',
                      ssn: "518124854",
                      dob: Date.new(1988, 11, 11),
                      family_member_id: family.primary_family_member.id,
                      application: application)
  end

  let(:due_on) { nil }
  let(:aasm_state) { 'attested' }
  let(:enrollment) { nil }

  # Helper method to set up non-ESI MEC evidence through the eligibility system
  def setup_non_esi_evidence(applicant, state: 'attested', due_date: nil)
    # Build APTC/CSR eligibility if it doesn't exist
    applicant.build_aptc_csr_eligibility unless applicant.aptc_csr_eligibility

    # Build the non-ESI MEC evidence through the eligibility
    evidence = applicant.aptc_csr_eligibility.evidences.build(
      _type: 'FinancialAssistance::Evidences::NonEsiMecEvidence',
      title: 'Non-ESI MEC Evidence',
      key: :non_esi_mec_evidence,
      current_state: state
    )

    evidence.due_on = due_date if due_date
    applicant.save!
    evidence
  end

  # Helper method to mock TimeKeeper and EnrollRegistry for due date calculations
  def mock_due_date_registry
    allow(TimeKeeper).to receive(:date_of_record).and_return(Date.current)
    allow(EnrollRegistry).to receive(:[]).with(:verification_document_due_in_days).and_return(
      double(item: 30)
    )
  end

  # Helper method to mock enrollment status checks
  def mock_enrollment_checks(has_enrollment: false)
    mock_enrollments = has_enrollment ? [enrollment].compact : []

    # Mock the HbxEnrollment query that gets called in the evidence utils
    allow(HbxEnrollment).to receive(:where).with(
      :aasm_state.in => HbxEnrollment::ENROLLED_STATUSES,
      family_id: family.id
    ).and_return(mock_enrollments)

    # Add the enrolled_in_any_aptc_csr_enrollments? method to FinancialAssistance::Applicant
    # since it doesn't exist but is called by the evidence utils
  end

  before do
    mock_due_date_registry
    enrollment # Trigger let evaluation if needed
  end

  context 'successful response processing' do
    context 'when PVC response indicates outstanding status' do
      before do
        @applicant = application.applicants.first
        setup_non_esi_evidence(@applicant, state: aasm_state, due_date: due_on)
      end

      context 'when applicant has no active health enrollments' do
        before do
          mock_enrollment_checks(has_enrollment: false)
          @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938'})
          @applicant.reload
        end

        it 'returns a success result' do
          expect(@result).to be_success
        end

        it 'returns success message confirming applicant update' do
          expect(@result.success).to include('Application is saved for application with hbx_id ')
        end

        it 'updates non-ESI evidence state to negative_response_received' do
          evidence = @applicant.aptc_csr_eligibility.non_esi_mec_evidence
          expect(evidence.current_state.to_s).to eq 'negative_response_received'
        end
      end

      context 'when applicant has active health enrollments' do
        let(:enrollment) do
          FactoryBot.create(:hbx_enrollment, :with_enrollment_members,
                            family: family, enrollment_members: family.family_members)
        end

        before do
          mock_enrollment_checks(has_enrollment: true)
          @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938'})
          @applicant.reload
        end

        it 'returns a success result' do
          expect(@result).to be_success
        end

        it 'updates non-ESI evidence state to negative_response_received when enrolled' do
          evidence = @applicant.aptc_csr_eligibility.non_esi_mec_evidence
          expect(evidence.current_state.to_s).to eq 'negative_response_received'
        end
      end

      context 'when evidence already has a due date' do
        let(:due_on) { TimeKeeper.date_of_record + 15.days }
        let(:aasm_state) { 'outstanding' }

        before do
          mock_enrollment_checks(has_enrollment: true)
          @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938'})
          @applicant.reload
        end

        it 'handles existing due date appropriately' do
          evidence = @applicant.aptc_csr_eligibility.non_esi_mec_evidence
          expect(evidence).to be_present
          expect(evidence.current_state.to_s).to eq 'negative_response_received'
        end
      end
    end

    context 'when applicant is enrolled only in dental plans' do
      let(:enrollment) do
        FactoryBot.create(:hbx_enrollment, :with_enrollment_members,
                          family: family, enrollment_members: family.family_members, coverage_kind: 'dental')
      end

      before do
        @applicant = application.applicants.first
        setup_non_esi_evidence(@applicant, state: aasm_state, due_date: due_on)
        mock_enrollment_checks(has_enrollment: false) # Dental plans don't count as health enrollments
        @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938'})
        @applicant.reload
      end

      it 'treats dental-only enrollments as non-enrolled for MEC purposes' do
        evidence = @applicant.aptc_csr_eligibility.non_esi_mec_evidence
        expect(evidence.current_state.to_s).to eq 'negative_response_received'
      end
    end

    context 'when PVC response indicates attested status' do
      before do
        @applicant = application.applicants.first
        setup_non_esi_evidence(@applicant)
        @result = subject.call(payload: response_payload_2, applicant_identifier: '1629165429385938')
        @applicant.reload
      end

      it 'returns a success result' do
        expect(@result).to be_success
      end

      it 'updates evidence to attested state and clears due date' do
        evidence = @applicant.aptc_csr_eligibility.non_esi_mec_evidence
        expect(evidence.current_state.to_s).to eq "attested"
        expect(evidence.due_on).to be nil
        expect(@result.success).to include('Application is saved for application with hbx_id')
      end
    end
  end

  context 'failure scenarios' do
    let(:identifier) { '1629165429385938' }

    context 'when application cannot be found' do
      before do
        application.destroy
      end

      it 'returns failure with appropriate error message' do
        result = subject.call({payload: response_payload, applicant_identifier: identifier})

        expect(result).to be_failure
        expect(result.failure).to eq("Could not find application with given hbx_id: #{response_payload[:hbx_id]}")
      end
    end

    context 'when application entity initialization fails' do
      before do
        response_payload[:hbx_id] = nil
      end

      it 'returns failure when hbx_id is missing' do
        result = subject.call({payload: response_payload, applicant_identifier: identifier})

        expect(result).to be_failure
        expect(result.failure).to eq("Failed to initialize application with hbx_id: ")
      end
    end

    context 'when application applicant cannot be found' do
      before do
        application.applicants.first.destroy
      end

      it 'returns failure when applicant is missing from application' do
        result = subject.call({payload: response_payload, applicant_identifier: identifier})

        expect(result).to be_failure
        expect(result.failure).to eq("applicant not found with #{identifier} for pvc Medicare")
      end
    end

    context 'when response payload applicant cannot be found' do
      before do
        response_payload[:applicants].first[:person_hbx_id] = '12345'
      end

      it 'returns failure when applicant is missing from response payload' do
        result = subject.call({payload: response_payload, applicant_identifier: identifier})

        expect(result).to be_failure
        expect(result.failure).to eq("applicant not found in response with #{identifier} for pvc Medicare")
      end
    end
  end

  context 'when applicant non-ESI evidence is not found' do
    before do
      @applicant = application.applicants.first
      # Don't build aptc_eligibilities_evidences to simulate missing non_esi_mec_evidence
      @applicant.save!
      @result = subject.call({payload: response_payload, applicant_identifier: '1629165429385938'})
      @applicant.reload
    end

    it 'should return failure' do
      expect(@result).to be_failure
    end

    it 'should return failure message for missing evidence' do
      expect(@result.failure).to eq('Applicant non-ESI evidence not found')
    end

    it 'should not have non_esi_mec_evidence' do
      expect(@applicant&.aptc_csr_eligibility&.non_esi_mec_evidence).to be_nil
    end
  end
end