# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::BaseReconcileEligibility, type: :model, dbclean: :around_each do

  let(:test_reconciler_class) do
    Class.new(described_class) do
      attr_accessor :test_eligibility, :applicable_result

      def initialize
        super
        @test_eligibility = nil
        @applicable_result = false
      end

      private

      def eligibility
        @test_eligibility
      end

      def applicable?
        @applicable_result
      end
    end
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :silver) }

  let(:application) do
    FactoryBot.create(:financial_assistance_application,
                      family_id: family.id,
                      aasm_state: 'determined',
                      assistance_year: TimeKeeper.date_of_record.year)
  end

  let(:applicant) do
    FactoryBot.create(:financial_assistance_applicant,
                      application: application,
                      is_primary_applicant: true,
                      family_member_id: family.primary_family_member.id)
  end

  let(:enrollment) do
    enrollment = FactoryBot.create(:hbx_enrollment,
                                   family: family,
                                   product: product,
                                   aasm_state: 'coverage_selected',
                                   hbx_id: 'test-enrollment-123')
    FactoryBot.create(:hbx_enrollment_member,
                      hbx_enrollment: enrollment,
                      applicant_id: applicant.family_member_id,
                      is_subscriber: true)
    enrollment
  end

  let(:active_applicant_enrollments) { [enrollment] }
  let(:eligibility_double) { double('Eligibility', present?: true, escalate_evidences_to_outstanding: true, downgrade_evidences_to_nrr: true) }

  let(:reconciler) { test_reconciler_class.new }

  let(:valid_params) do
    {
      applicant: applicant,
      active_applicant_enrollments: active_applicant_enrollments,
      enrollment: enrollment
    }
  end

  describe '#call' do
    before do
      reconciler.test_eligibility = eligibility_double
      allow(eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(eligibility_double).to receive(:downgrade_evidences_to_nrr)
    end

    context 'with valid parameters' do
      it 'validates parameters and performs reconciliation successfully' do
        result = reconciler.call(valid_params)
        expect(result).to be_success
      end

      it 'returns success with reconciled true when reconciliation is needed' do
        reconciler.test_eligibility = eligibility_double

        result = reconciler.call(valid_params)

        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
        expect(result.value![:eligibility]).to eq(eligibility_double)
      end

      context 'when reconciliation is not needed' do
        before do
          reconciler.test_eligibility = nil
        end

        it 'returns success with reconciled false and reason' do
          result = reconciler.call(valid_params)

          expect(result).to be_success
          expect(result.value![:reconciled]).to be false
          expect(result.value![:reason]).to eq('No reconciliation needed')
        end
      end
    end

    context 'with invalid parameters' do
      it 'fails when applicant is missing' do
        params = valid_params.except(:applicant)
        result = reconciler.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Missing applicant')
      end

      it 'fails when enrollment is missing' do
        params = valid_params.except(:enrollment)
        result = reconciler.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Missing enrollment')
      end

      it 'fails when active_applicant_enrollments is missing' do
        params = valid_params.except(:active_applicant_enrollments)
        result = reconciler.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Missing active_applicant_enrollments')
      end
    end

    context 'when reconciliation raises an error' do
      before do
        reconciler.test_eligibility = eligibility_double
        reconciler.applicable_result = true
        allow(eligibility_double).to receive(:escalate_evidences_to_outstanding)
          .and_raise(StandardError.new('Test error'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)

        expect(result).to be_failure
        expect(result.failure).to include('Reconciliation failed: Test error')
      end
    end
  end

  describe '#needs_reconciliation? (private method)' do
    context 'when eligibility is present' do
      before do
        reconciler.test_eligibility = eligibility_double
        reconciler.call(valid_params)
      end

      it 'returns true' do
        expect(reconciler.send(:needs_reconciliation?)).to be true
      end
    end

    context 'when eligibility is not present' do
      before do
        reconciler.test_eligibility = double('Eligibility', present?: false)
        reconciler.call(valid_params)
      end

      it 'returns false' do
        expect(reconciler.send(:needs_reconciliation?)).to be false
      end
    end

    context 'when eligibility is nil' do
      before do
        reconciler.test_eligibility = nil
        reconciler.call(valid_params)
      end

      it 'returns false' do
        expect(reconciler.send(:needs_reconciliation?)).to be false
      end
    end
  end

  describe '#reconcile (private method)' do
    let(:action) { 'enrollment_purchase' }
    let(:message) { "Enrollment #{enrollment.hbx_id} has been purchased" }

    before do
      reconciler.test_eligibility = eligibility_double
      allow(eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(eligibility_double).to receive(:downgrade_evidences_to_nrr)
      reconciler.call(valid_params)
    end

    context 'when eligibility is applicable' do
      before do
        reconciler.applicable_result = true
      end

      it 'calls escalate_evidences_to_outstanding on the eligibility' do
        expect(eligibility_double).to receive(:escalate_evidences_to_outstanding).with(action, message)
        reconciler.send(:reconcile)
      end
    end

    context 'when eligibility is not applicable' do
      before do
        reconciler.applicable_result = false
      end

      it 'calls downgrade_evidences_to_nrr on the eligibility' do
        expect(eligibility_double).to receive(:downgrade_evidences_to_nrr).with(action, message)
        reconciler.send(:reconcile)
      end
    end
  end

  describe 'abstract methods' do
    describe '#applicable?' do
      it 'raises NotImplementedError in base class' do
        base_reconciler = described_class.new
        expect do
          base_reconciler.send(:applicable?)
        end.to raise_error(NotImplementedError, 'Subclasses must implement #applicable?')
      end
    end

    describe '#eligibility' do
      it 'raises NotImplementedError in base class' do
        base_reconciler = described_class.new
        expect do
          base_reconciler.send(:eligibility)
        end.to raise_error(NotImplementedError, 'Subclasses must implement #eligibility')
      end
    end
  end

  describe '#applicant_enrolled? (private method)' do
    before do
      reconciler.call(valid_params)
    end

    context 'when active_applicant_enrollments is present and has enrollments' do
      it 'returns true' do
        expect(reconciler.send(:applicant_enrolled?)).to be true
      end
    end

    context 'when active_applicant_enrollments is empty' do
      let(:empty_enrollments) { [] }

      before do
        reconciler.call(valid_params.merge(active_applicant_enrollments: empty_enrollments))
      end

      it 'returns false' do
        expect(reconciler.send(:applicant_enrolled?)).to be false
      end
    end
  end

  describe 'integration with enrollment context' do
    let(:hbx_id) { 'TEST_HBX_ID_123' }
    let(:enrollment_with_hbx_id) do
      FactoryBot.create(:hbx_enrollment,
                        family: family,
                        product: product,
                        aasm_state: 'coverage_selected',
                        hbx_id: hbx_id)
    end

    before do
      reconciler.test_eligibility = eligibility_double
      reconciler.applicable_result = true
      allow(eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(eligibility_double).to receive(:downgrade_evidences_to_nrr)
    end

    it 'uses correct enrollment context in adjustment messages' do
      expected_message = "Enrollment #{hbx_id} has been purchased"
      expected_action = 'enrollment_purchase'

      expect(eligibility_double).to receive(:escalate_evidences_to_outstanding).with(expected_action, expected_message)

      reconciler.call(valid_params.merge(enrollment: enrollment_with_hbx_id))
    end
  end
end
