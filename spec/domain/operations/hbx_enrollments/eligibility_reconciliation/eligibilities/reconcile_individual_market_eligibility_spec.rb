# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileIndividualMarketEligibility, type: :model, dbclean: :around_each do
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
                                   hbx_id: 'TEST_HBX_ID')
    FactoryBot.create(:hbx_enrollment_member,
                      hbx_enrollment: enrollment,
                      applicant_id: applicant.family_member_id,
                      is_subscriber: true)
    enrollment
  end

  let(:active_applicant_enrollments) { [enrollment] }
  let(:individual_market_eligibility_double) { double('IndividualMarketEligibility', present?: true, escalate_evidences_to_outstanding: true, downgrade_evidences_to_nrr: true) }

  let(:reconciler) { described_class.new }

  let(:valid_params) do
    {
      applicant: applicant,
      active_applicant_enrollments: active_applicant_enrollments,
      enrollment: enrollment
    }
  end

  before do
    allow(applicant).to receive(:individual_market_eligibility).and_return(individual_market_eligibility_double)
  end

  describe 'inheritance' do
    it 'inherits from BaseReconcileEligibility' do
      expect(described_class).to be < Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::BaseReconcileEligibility
    end
  end

  describe '#call' do
    before do
      allow(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(individual_market_eligibility_double).to receive(:downgrade_evidences_to_nrr)
    end

    context 'with valid parameters' do
      it 'validates parameters and performs reconciliation successfully' do
        result = reconciler.call(valid_params)
        expect(result).to be_success
      end

      it 'returns success with reconciled true when reconciliation is needed' do
        result = reconciler.call(valid_params)

        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
        expect(result.value![:eligibility]).to eq(individual_market_eligibility_double)
      end

      context 'when reconciliation is not needed' do
        before do
          allow(applicant).to receive(:individual_market_eligibility).and_return(nil)
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
        allow(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
          .and_raise(StandardError.new('Individual market error'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)

        expect(result).to be_failure
        expect(result.failure).to include('Reconciliation failed: Individual market error')
      end
    end
  end

  describe '#needs_reconciliation? (private method)' do
    context 'when individual market eligibility is present' do
      before do
        reconciler.call(valid_params)
      end

      it 'returns true' do
        expect(reconciler.send(:needs_reconciliation?)).to be true
      end
    end

    context 'when individual market eligibility is not present' do
      before do
        allow(applicant).to receive(:individual_market_eligibility).and_return(double('Eligibility', present?: false))
        reconciler.call(valid_params)
      end

      it 'returns false' do
        expect(reconciler.send(:needs_reconciliation?)).to be false
      end
    end

    context 'when individual market eligibility is nil' do
      before do
        allow(applicant).to receive(:individual_market_eligibility).and_return(nil)
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
      allow(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(individual_market_eligibility_double).to receive(:downgrade_evidences_to_nrr)
      reconciler.call(valid_params)
    end

    context 'when eligibility is applicable (applicant is enrolled)' do
      it 'calls escalate_evidences_to_outstanding on the individual market eligibility' do
        expect(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding).with(action, message)
        reconciler.send(:reconcile)
      end

      it 'does not call downgrade_evidences_to_nrr' do
        expect(individual_market_eligibility_double).not_to receive(:downgrade_evidences_to_nrr)
        reconciler.send(:reconcile)
      end
    end

    context 'when eligibility is not applicable (applicant is not enrolled)' do
      let(:active_applicant_enrollments) { [] }

      before do
        reconciler.call(valid_params.merge(active_applicant_enrollments: active_applicant_enrollments))
      end

      it 'calls downgrade_evidences_to_nrr on the individual market eligibility' do
        expect(individual_market_eligibility_double).to receive(:downgrade_evidences_to_nrr).with(action, message)
        reconciler.send(:reconcile)
      end

      it 'does not call escalate_evidences_to_outstanding' do
        expect(individual_market_eligibility_double).not_to receive(:escalate_evidences_to_outstanding)
        reconciler.send(:reconcile)
      end
    end
  end

  describe '#eligibility (private method)' do
    before do
      reconciler.call(valid_params)
    end

    it 'returns the individual market eligibility from the applicant' do
      expect(reconciler.send(:eligibility)).to eq(individual_market_eligibility_double)
    end

    it 'calls the individual_market_eligibility method on the applicant' do
      expect(applicant).to receive(:individual_market_eligibility).and_return(individual_market_eligibility_double)
      reconciler.send(:eligibility)
    end
  end

  describe '#applicable? (private method)' do
    before do
      reconciler.call(valid_params)
    end

    context 'when applicant has active enrollments' do
      it 'returns true' do
        expect(reconciler.send(:applicable?)).to be true
      end
    end

    context 'when applicant has multiple active enrollments' do
      let(:second_enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family,
                          product: product,
                          aasm_state: 'coverage_selected')
      end
      let(:active_applicant_enrollments) { [enrollment, second_enrollment] }

      before do
        reconciler.call(valid_params.merge(active_applicant_enrollments: active_applicant_enrollments))
      end

      it 'returns true' do
        expect(reconciler.send(:applicable?)).to be true
      end
    end

    context 'when applicant has no active enrollments' do
      let(:active_applicant_enrollments) { [] }

      before do
        reconciler.call(valid_params.merge(active_applicant_enrollments: active_applicant_enrollments))
      end

      it 'returns false' do
        expect(reconciler.send(:applicable?)).to be false
      end
    end

    it 'uses simpler membership-based logic (same as applicant_enrolled?)' do
      expect(reconciler.send(:applicable?)).to eq(reconciler.send(:applicant_enrolled?))
    end
  end

  describe 'business logic differences from APTC/CSR reconciler' do
    before do
      allow(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
    end

    it 'does not restrict by enrollment type (new vs renewal)' do
      renewal_enrollment = FactoryBot.create(:hbx_enrollment,
                                             family: family,
                                             product: product,
                                             aasm_state: 'coverage_selected')

      renewal_params = {
        applicant: applicant,
        active_applicant_enrollments: [renewal_enrollment],
        enrollment: renewal_enrollment
      }

      expect(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      result = reconciler.call(renewal_params)
      expect(result).to be_success
    end

    it 'does not restrict by coverage type (health vs dental)' do
      # Individual Market processes both health and dental enrollments
      dental_product = FactoryBot.create(:benefit_markets_products_dental_products_dental_product)
      dental_enrollment = FactoryBot.create(:hbx_enrollment,
                                            family: family,
                                            product: dental_product,
                                            aasm_state: 'coverage_selected')

      dental_params = {
        applicant: applicant,
        active_applicant_enrollments: [dental_enrollment],
        enrollment: dental_enrollment
      }

      expect(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      result = reconciler.call(dental_params)
      expect(result).to be_success
    end
  end

  describe 'integration scenarios' do
    before do
      allow(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(individual_market_eligibility_double).to receive(:downgrade_evidences_to_nrr)
    end

    context 'when reconciling after enrollment purchase' do
      it 'requires eligibility evidences for newly enrolled member' do
        expect(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding).with(
          'enrollment_purchase',
          "Enrollment #{enrollment.hbx_id} has been purchased"
        )

        result = reconciler.call(valid_params)
        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
      end
    end

    context 'when reconciling after enrollment termination' do
      let(:active_applicant_enrollments) { [] }

      it 'waives eligibility evidences for member with no active enrollments' do
        expect(individual_market_eligibility_double).to receive(:downgrade_evidences_to_nrr).with(
          'enrollment_purchase',
          "Enrollment #{enrollment.hbx_id} has been purchased"
        )

        result = reconciler.call(valid_params.merge(active_applicant_enrollments: active_applicant_enrollments))
        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
      end
    end

    context 'with multiple family members' do
      let(:second_family_member) { FactoryBot.create(:family_member, family: family) }
      let(:second_enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family,
                          product: product,
                          aasm_state: 'coverage_selected')
      end
      let(:active_applicant_enrollments) { [enrollment, second_enrollment] }

      it 'correctly identifies applicant enrollment status' do
        expect(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
        result = reconciler.call(valid_params.merge(active_applicant_enrollments: active_applicant_enrollments))
        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
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
      allow(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding)
    end

    it 'uses correct enrollment context in adjustment messages' do
      expected_message = "Enrollment #{hbx_id} has been purchased"
      expected_action = 'enrollment_purchase'

      expect(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding).with(expected_action, expected_message)

      reconciler.call(valid_params.merge(enrollment: enrollment_with_hbx_id))
    end
  end

  describe 'error handling' do
    context 'when individual market eligibility method is not available' do
      before do
        allow(applicant).to receive(:individual_market_eligibility).and_raise(NoMethodError.new('Method not found'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)
        expect(result).to be_failure
        expect(result.failure).to include('Reconciliation failed: Method not found')
      end
    end

    context 'when eligibility operations raise errors' do
      before do
        allow(individual_market_eligibility_double).to receive(:escalate_evidences_to_outstanding).and_raise(StandardError.new('Evidence error'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)
        expect(result).to be_failure
        expect(result.failure).to eq('Reconciliation failed: Evidence error')
      end
    end
  end
end
