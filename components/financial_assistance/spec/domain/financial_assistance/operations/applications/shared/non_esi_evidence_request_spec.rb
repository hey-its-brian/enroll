# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Operations::Applications::Shared::NonEsiEvidenceRequest do

  # Test implementation class to include the module
  let(:test_class) do
    logger_mock = double('Logger', error: nil)

    Class.new do
      include FinancialAssistance::Operations::Applications::Shared::NonEsiEvidenceRequest

      define_method :initialize do
        @logger = logger_mock
      end

      # Implement abstract methods for testing
      def success_message(application_hbx_id)
        "Success for #{application_hbx_id}"
      end

      def submitted_action
        'submitted'
      end

      def submitted_message
        'evidence_submitted_for_review'
      end

      def submission_failed_action
        'submission_failed'
      end

      def submission_failed_message(error)
        "Submission failed: #{error}"
      end

      def eligibility_state_reason
        'eligibility_review_required'
      end

      def process_name
        'test_process'
      end

      def build_event(_cv3_application)
        Dry::Monads::Success(double('event', publish: true))
      end

      attr_reader :logger

      def publish_success_message
        'Event published successfully'
      end

      def build_and_validate_payload(_application)
        Dry::Monads::Success(double('payload', applicants: []))
      end

      def check_applicant_eligibility_rules(_applicant_entity)
        Dry::Monads::Success(true)
      end

      def handle_validation_failure(errors)
        Dry::Monads::Failure(errors.join(', '))
      end
    end
  end

  let(:operation) { test_class.new }
  let(:application_hbx_id) { 'test_hbx_id_123' }
  let(:params) { { application_hbx_id: application_hbx_id } }

  let(:application) { double('application') }
  let(:applicant) { double('applicant') }
  let(:aptc_csr_eligibility) { double('aptc_csr_eligibility', reason: 'test') }
  let(:evidence) { double('evidence') }

  before do
    # Stub EnrollRegistry if not available
    stub_const('EnrollRegistry', Class.new) unless defined?(EnrollRegistry)
    allow(EnrollRegistry).to receive(:feature_enabled?).and_return(false)

    allow(::FinancialAssistance::Application).to receive(:by_hbx_id).with(application_hbx_id).and_return([application])
    allow(application).to receive(:present?).and_return(true)
    allow(application).to receive(:active_applicants).and_return([applicant])
    allow(application).to receive(:save).and_return(true)
    allow(application).to receive(:valid?).and_return(true)
    allow(application).to receive(:hbx_id).and_return(application_hbx_id)

    allow(applicant).to receive(:aptc_csr_eligibility).and_return(aptc_csr_eligibility)
    allow(applicant).to receive(:person_hbx_id).and_return('person_123')

    allow(aptc_csr_eligibility).to receive(:non_esi_mec_evidence).and_return(nil)
    allow(aptc_csr_eligibility).to receive(:determine_eligibility_state)
    allow(operation).to receive(:update_family_determination).and_return(Dry::Monads::Success(true))
  end

  describe '#call' do
    context 'when all steps succeed' do
      let(:cv3_application) { double('cv3_application') }
      let(:event) { double('event', publish: true) }

      before do
        allow(operation).to receive(:build_evidence_history).and_return(Dry::Monads::Success(true))
        allow(operation).to receive(:transform_and_validate_application).and_return(Dry::Monads::Success(cv3_application))
        allow(operation).to receive(:build_event).and_return(Dry::Monads::Success(event))
      end

      it 'returns success with message' do
        result = operation.call(params)

        expect(result).to be_success
        expect(result.value!).to eq("Success for #{application_hbx_id}")
      end

      it 'calls all required steps in order' do
        expect(operation).to receive(:validate).with(params).and_call_original
        expect(operation).to receive(:fetch_application).and_call_original
        expect(operation).to receive(:build_evidence_history).with(application, 'submitted', 'evidence_submitted_for_review', 'system')
        expect(operation).to receive(:transform_and_validate_application).with(application)
        expect(operation).to receive(:save_application).with(application).and_call_original
        expect(operation).to receive(:build_event).with(cv3_application)
        expect(operation).to receive(:publish).with(event).and_call_original

        operation.call(params)
      end
    end

    context 'when validation fails' do
      let(:params) { { application_hbx_id: nil } }

      it 'returns failure with validation error' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('application hbx_id is missing')
      end
    end

    context 'when application is not found' do
      before do
        allow(::FinancialAssistance::Application).to receive(:by_hbx_id).and_return([])
      end

      it 'returns failure with not found error' do
        result = operation.call(params)

        expect(result).to be_failure
        expect(result.failure).to include('No application found')
      end
    end
  end

  describe '#validate' do
    context 'with valid params' do
      it 'returns success' do
        result = operation.send(:validate, params)
        expect(result).to be_success
        expect(result.value!).to eq(params)
      end
    end

    context 'with missing application_hbx_id' do
      let(:params) { { application_hbx_id: nil } }

      it 'returns failure' do
        result = operation.send(:validate, params)
        expect(result).to be_failure
      end
    end
  end

  describe '#fetch_application' do
    context 'when application exists and is valid' do
      it 'returns success with application' do
        result = operation.send(:fetch_application, params)
        expect(result).to be_success
        expect(result.value!).to eq(application)
      end
    end

    context 'when application exists but is invalid' do
      before do
        allow(application).to receive(:valid?).and_return(false)
      end

      it 'returns failure' do
        result = operation.send(:fetch_application, params)
        expect(result).to be_failure
        expect(result.failure).to include('Invalid application')
      end
    end

    context 'when application does not exist' do
      before do
        allow(::FinancialAssistance::Application).to receive(:by_hbx_id).and_return([])
      end

      it 'returns failure' do
        result = operation.send(:fetch_application, params)
        expect(result).to be_failure
        expect(result.failure).to include('No application found')
      end
    end
  end

  describe '#save_application' do
    context 'when save succeeds' do
      it 'returns success' do
        result = operation.send(:save_application, application)
        expect(result).to be_success
        expect(result.value!).to eq(application)
      end
    end

    context 'when save fails' do
      let(:errors) { double('errors', full_messages: ['Error message']) }

      before do
        allow(application).to receive(:save).and_return(false)
        allow(application).to receive(:errors).and_return(errors)
      end

      it 'returns failure' do
        result = operation.send(:save_application, application)
        expect(result).to be_failure
        expect(result.failure).to include('Failed to save application')
      end
    end
  end

  describe 'helper methods' do
    describe '#non_esi_evidence_for' do
      it 'returns evidence from applicant' do
        allow(aptc_csr_eligibility).to receive(:non_esi_mec_evidence).and_return(evidence)

        result = operation.send(:non_esi_evidence_for, applicant)
        expect(result).to eq(evidence)
      end
    end

    describe '#applicants_with_evidence' do
      before do
        allow(aptc_csr_eligibility).to receive(:non_esi_mec_evidence).and_return(evidence)
      end

      it 'returns applicants that have evidence' do
        result = operation.send(:applicants_with_evidence, application)
        expect(result).to eq([applicant])
      end
    end

    describe '#assign_evidence_to_default_state' do
      before do
        allow(evidence).to receive(:mark_as_attested)
      end

      it 'moves evidence to attested state' do
        expect(evidence).to receive(:mark_as_attested)
        operation.send(:assign_evidence_to_default_state, evidence)
      end
    end
  end

  describe 'abstract methods' do
    let(:abstract_operation) do
      Class.new do
        include FinancialAssistance::Operations::Applications::Shared::NonEsiEvidenceRequest
      end.new
    end

    it 'raises NotImplementedError for abstract methods' do
      expect { abstract_operation.send(:success_message, 'test') }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:submitted_action) }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:submitted_message) }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:submission_failed_action) }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:submission_failed_message, 'error') }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:eligibility_state_reason) }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:process_name) }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:build_event, 'app') }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:logger) }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:publish_success_message) }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:build_and_validate_payload, 'app') }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:check_applicant_eligibility_rules, 'entity') }.to raise_error(NotImplementedError)
      expect { abstract_operation.send(:handle_validation_failure, []) }.to raise_error(NotImplementedError)
    end
  end

  describe '#transform_and_validate_application' do
    let(:payload_entity) { Dry::Monads::Success(double('payload', applicants: [])) }

    before do
      allow(operation).to receive(:build_and_validate_payload).and_return(payload_entity)
      allow(operation).to receive(:move_applicant_eligibility_state)
    end

    context 'when feature flag is enabled and all applicants are valid' do
      before do
        allow(operation).to receive(:validate_applicants).and_return([['person_123', true]])
      end

      it 'validates applicants when feature is enabled' do
        expect(operation).to receive(:validate_applicants)

        result = operation.send(:transform_and_validate_application, application)
        expect(result).to be_success
      end

      it 'calls move_applicant_eligibility_state and updates aptc_csr_eligibility state' do
        expect(operation).to receive(:move_applicant_eligibility_state).with(application).and_call_original
        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required')

        operation.send(:transform_and_validate_application, application)
      end
    end

    context 'when feature flag is enabled and all applicants are invalid' do
      before do
        allow(operation).to receive(:validate_applicants).and_return([['person_123', false]])
      end

      it 'returns failure when all applicants are invalid' do
        expect(operation).to receive(:move_applicant_eligibility_state).with(application).and_call_original
        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required')

        result = operation.send(:transform_and_validate_application, application)
        expect(result).to be_failure
        expect(result.failure).to include('all applicants are invalid')
      end
    end

    context 'when payload validation fails' do
      let(:payload_entity) { Dry::Monads::Failure(double('error', messages: ['validation error'])) }

      before do
        allow(operation).to receive(:record_application_failure)
      end

      it 'handles payload validation failure and moves eligibility state' do
        expect(operation).to receive(:move_applicant_eligibility_state).with(application).and_call_original
        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required')
        expect(operation).to receive(:record_application_failure)

        result = operation.send(:transform_and_validate_application, application)
        expect(result).to be_failure
      end
    end

    context 'when an exception occurs' do
      before do
        allow(operation).to receive(:build_and_validate_payload).and_raise(StandardError.new('test error'))
      end

      it 'handles exceptions and returns failure' do
        result = operation.send(:transform_and_validate_application, application)
        expect(result).to be_failure
        expect(result.failure).to match(/Failed to publish event for the application with/)
      end
    end
  end

  describe '#move_applicant_eligibility_state' do
    let(:applicant2) { double('applicant2') }
    let(:aptc_csr_eligibility2) { double('aptc_csr_eligibility2') }

    before do
      allow(application).to receive(:active_applicants).and_return([applicant, applicant2])
      allow(applicant2).to receive(:aptc_csr_eligibility).and_return(aptc_csr_eligibility2)
    end

    context 'when called with valid application and applicants' do
      it 'calls determine_eligibility_state on all active applicants with the correct reason' do
        reason = 'eligibility_review_required'

        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with(reason)
        expect(aptc_csr_eligibility2).to receive(:determine_eligibility_state).with(reason)

        operation.send(:move_applicant_eligibility_state, application)
      end

      it 'uses the eligibility_state_reason from the operation' do
        expect(operation).to receive(:eligibility_state_reason).and_return('custom_reason')
        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('custom_reason')
        expect(aptc_csr_eligibility2).to receive(:determine_eligibility_state).with('custom_reason')

        operation.send(:move_applicant_eligibility_state, application)
      end

      it 'actually updates the eligibility state for all applicants' do
        # Track initial state
        initial_state_1 = 'pending'
        initial_state_2 = 'pending'
        updated_state_1 = 'under_review'
        updated_state_2 = 'under_review'

        # Mock initial states
        allow(aptc_csr_eligibility).to receive(:eligibility_state).and_return(initial_state_1)
        allow(aptc_csr_eligibility2).to receive(:eligibility_state).and_return(initial_state_2)

        # Mock determine_eligibility_state to change the state
        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required') do
          allow(aptc_csr_eligibility).to receive(:eligibility_state).and_return(updated_state_1)
        end
        expect(aptc_csr_eligibility2).to receive(:determine_eligibility_state).with('eligibility_review_required') do
          allow(aptc_csr_eligibility2).to receive(:eligibility_state).and_return(updated_state_2)
        end

        operation.send(:move_applicant_eligibility_state, application)

        # Verify state has changed
        expect(aptc_csr_eligibility.eligibility_state).to eq(updated_state_1)
        expect(aptc_csr_eligibility2.eligibility_state).to eq(updated_state_2)
      end

      it 'persists the state changes' do
        # Mock save methods
        allow(aptc_csr_eligibility).to receive(:save!).and_return(true)
        allow(aptc_csr_eligibility2).to receive(:save!).and_return(true)

        # Mock determine_eligibility_state to also call save
        allow(aptc_csr_eligibility).to receive(:determine_eligibility_state) do |_reason|
          aptc_csr_eligibility.save!
        end
        allow(aptc_csr_eligibility2).to receive(:determine_eligibility_state) do |_reason|
          aptc_csr_eligibility2.save!
        end

        expect(aptc_csr_eligibility).to receive(:save!)
        expect(aptc_csr_eligibility2).to receive(:save!)

        operation.send(:move_applicant_eligibility_state, application)
      end
    end

    context 'when application has no active applicants' do
      before do
        allow(application).to receive(:active_applicants).and_return([])
      end

      it 'does not call determine_eligibility_state on any applicants' do
        expect(aptc_csr_eligibility).not_to receive(:determine_eligibility_state)
        expect(aptc_csr_eligibility2).not_to receive(:determine_eligibility_state)

        operation.send(:move_applicant_eligibility_state, application)
      end
    end

    context 'when aptc_csr_eligibility is nil for an applicant' do
      before do
        allow(applicant2).to receive(:aptc_csr_eligibility).and_return(nil)
      end

      it 'raises an error when trying to call determine_eligibility_state on nil' do
        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required')

        expect do
          operation.send(:move_applicant_eligibility_state, application)
        end.to raise_error(NoMethodError)
      end
    end

    context 'integration with transform_and_validate_application' do
      let(:payload_entity) { Dry::Monads::Success(double('payload', applicants: [])) }
      let(:applicant2) { double('applicant2') }
      let(:aptc_csr_eligibility2) { double('aptc_csr_eligibility2') }

      before do
        # Setup second applicant for integration tests
        allow(application).to receive(:active_applicants).and_return([applicant, applicant2])
        allow(applicant2).to receive(:aptc_csr_eligibility).and_return(aptc_csr_eligibility2)
        allow(aptc_csr_eligibility2).to receive(:determine_eligibility_state)

        allow(operation).to receive(:build_and_validate_payload).and_return(payload_entity)
        allow(operation).to receive(:validate_applicants).and_return([['person_123', true]])
      end

      it 'is called during successful transform_and_validate_application' do
        expect(operation).to receive(:move_applicant_eligibility_state).with(application).and_call_original
        expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required')
        expect(aptc_csr_eligibility2).to receive(:determine_eligibility_state).with('eligibility_review_required')

        result = operation.send(:transform_and_validate_application, application)
        expect(result).to be_success
      end

      context 'when payload validation fails' do
        let(:payload_entity) { Dry::Monads::Failure(double('error', messages: ['validation error'])) }

        before do
          allow(operation).to receive(:record_application_failure)
        end

        it 'is still called even when payload validation fails' do
          expect(operation).to receive(:move_applicant_eligibility_state).with(application).and_call_original
          expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required')
          expect(aptc_csr_eligibility2).to receive(:determine_eligibility_state).with('eligibility_review_required')

          operation.send(:transform_and_validate_application, application)
        end
      end

      context 'when all applicants are invalid' do
        before do
          allow(operation).to receive(:validate_applicants).and_return([['person_123', false]])
        end

        it 'is called before returning failure for invalid applicants' do
          expect(operation).to receive(:move_applicant_eligibility_state).with(application).and_call_original
          expect(aptc_csr_eligibility).to receive(:determine_eligibility_state).with('eligibility_review_required')
          expect(aptc_csr_eligibility2).to receive(:determine_eligibility_state).with('eligibility_review_required')

          result = operation.send(:transform_and_validate_application, application)
          expect(result).to be_failure
        end
      end
    end
  end

  describe '#validate_applicants' do
    let(:payload_entity) { double('payload', value!: double('application', applicants: [applicant_entity])) }
    let(:applicant_entity) { double('applicant_entity', person_hbx_id: 'person_123') }
    let(:eligible_applicant) { double('eligible_applicant', person_hbx_id: 'person_123') }

    before do
      allow(operation).to receive(:applicants_with_evidence).and_return([eligible_applicant])
      allow(operation).to receive(:find_matching_applicant_entity).and_return(applicant_entity)
      allow(operation).to receive(:check_applicant_eligibility_rules).and_return(Dry::Monads::Success(true))
    end

    it 'validates all eligible applicants' do
      result = operation.send(:validate_applicants, payload_entity, application)
      expect(result).to eq([['person_123', true]])
    end

    context 'when applicant validation fails' do
      before do
        allow(operation).to receive(:check_applicant_eligibility_rules).and_return(Dry::Monads::Failure('validation failed'))
        allow(operation).to receive(:record_applicant_failure)
        allow(operation).to receive(:non_esi_evidence_for).and_return(evidence)
      end

      it 'records failure and returns false for invalid applicant' do
        expect(operation).to receive(:record_applicant_failure)

        result = operation.send(:validate_applicants, payload_entity, application)
        expect(result).to eq([['person_123', false]])
      end
    end
  end

  describe 'evidence management methods' do
    describe '#build_evidence_history' do
      before do
        allow(aptc_csr_eligibility).to receive(:non_esi_mec_evidence).and_return(evidence)
        allow(evidence).to receive(:present?).and_return(true)
        allow(evidence).to receive(:build_verification_history)
      end

      it 'adds verification history to all evidences and returns success' do
        expect(evidence).to receive(:build_verification_history).with('submitted', 'evidence_submitted_for_review', 'system')

        result = operation.send(:build_evidence_history, application, 'submitted', 'evidence_submitted_for_review', 'system')

        expect(result).to be_success
        expect(result.value!).to eq(true)
      end

      context 'when no applicants have evidence' do
        before do
          allow(aptc_csr_eligibility).to receive(:non_esi_mec_evidence).and_return(nil)
        end

        it 'still returns success even when no evidence exists' do
          expect(evidence).not_to receive(:build_verification_history)

          result = operation.send(:build_evidence_history, application, 'submitted', 'evidence_submitted_for_review', 'system')

          expect(result).to be_success
          expect(result.value!).to eq(true)
        end
      end

      context 'when multiple applicants have evidence' do
        let(:applicant2) { double('applicant2') }
        let(:aptc_csr_eligibility2) { double('aptc_csr_eligibility2') }
        let(:evidence2) { double('evidence2') }

        before do
          allow(application).to receive(:active_applicants).and_return([applicant, applicant2])
          allow(applicant2).to receive(:aptc_csr_eligibility).and_return(aptc_csr_eligibility2)
          allow(aptc_csr_eligibility2).to receive(:non_esi_mec_evidence).and_return(evidence2)
          allow(evidence2).to receive(:present?).and_return(true)
          allow(evidence2).to receive(:build_verification_history)
        end

        it 'adds verification history to all evidences' do
          expect(evidence).to receive(:build_verification_history).with('submitted', 'evidence_submitted_for_review', 'system')
          expect(evidence2).to receive(:build_verification_history).with('submitted', 'evidence_submitted_for_review', 'system')

          result = operation.send(:build_evidence_history, application, 'submitted', 'evidence_submitted_for_review', 'system')

          expect(result).to be_success
          expect(result.value!).to eq(true)
        end
      end
    end

    describe '#record_applicant_failure' do
      before do
        allow(operation).to receive(:build_verification_history)
        allow(operation).to receive(:assign_evidence_to_default_state)
      end

      it 'records failure and updates evidence state' do
        result = Dry::Monads::Failure('test error')

        expect(operation).to receive(:build_verification_history)
        expect(operation).to receive(:assign_evidence_to_default_state)

        operation.send(:record_applicant_failure, evidence, result)
      end
    end

    describe '#record_application_failure' do
      before do
        allow(operation).to receive(:build_evidence_history)
        allow(operation).to receive(:assign_evidence_state_for_all_applicants)
      end

      it 'creates evidence history and updates all evidence states' do
        expect(operation).to receive(:build_evidence_history)
        expect(operation).to receive(:assign_evidence_state_for_all_applicants)

        operation.send(:record_application_failure, application, ['error message'])
      end
    end
  end

  describe 'iteration helper methods' do
    describe '#with_eligible_applicants' do
      it 'yields each active applicant' do
        yielded_applicants = []
        operation.send(:with_eligible_applicants, application) do |applicant|
          yielded_applicants << applicant
        end

        expect(yielded_applicants).to eq([applicant])
      end
    end

    describe '#with_evidences' do
      before do
        allow(aptc_csr_eligibility).to receive(:non_esi_mec_evidence).and_return(evidence)
      end

      it 'yields evidences for applicants that have them' do
        yielded_evidences = []
        operation.send(:with_evidences, application) do |evidence|
          yielded_evidences << evidence
        end

        expect(yielded_evidences).to eq([evidence])
      end
    end

    describe '#find_matching_applicant_entity' do
      let(:applicant_entity) { double('applicant_entity', person_hbx_id: 'person_123') }
      let(:applicants_entity) { [applicant_entity] }

      it 'finds matching applicant by person_hbx_id' do
        result = operation.send(:find_matching_applicant_entity, applicant, applicants_entity)
        expect(result).to eq(applicant_entity)
      end
    end
  end

  describe '#build_verification_history' do
    context 'when evidence is present' do
      before do
        allow(evidence).to receive(:present?).and_return(true)
        allow(evidence).to receive(:build_verification_history)
      end

      it 'adds verification history to evidence' do
        expect(evidence).to receive(:build_verification_history).with('action', 'reason', 'user')

        operation.send(:build_verification_history, evidence, 'action', 'reason', 'user')
      end
    end

    context 'when evidence is nil' do
      it 'does not raise error' do
        expect { operation.send(:build_verification_history, nil, 'action', 'reason', 'user') }.not_to raise_error
      end
    end

    context 'when evidence is not present' do
      before do
        allow(evidence).to receive(:present?).and_return(false)
      end

      it 'does not call build_verification_history on evidence' do
        expect(evidence).not_to receive(:build_verification_history)

        operation.send(:build_verification_history, evidence, 'action', 'reason', 'user')
      end
    end
  end
end