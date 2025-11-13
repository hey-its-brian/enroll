# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::HbxEnrollments::OnSave,
               type: :model,
               dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :silver) }
  let(:enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      family: family,
                      product: product,
                      aasm_state: 'coverage_selected')
  end

  subject { described_class.new }

  describe '#call' do
    context 'with valid enrollment GID' do
      let(:params) { { gid: enrollment.to_global_id.to_s } }

      before do
        allow(Operations::Eligibilities::BuildFamilyDetermination).to receive(:new)
          .and_return(double('family_determination_operation', call: Dry::Monads::Success(double('Determination'))))
      end

      context 'when reconciliation succeeds' do
        before do
          allow(Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment).to receive(:new)
            .and_return(double('reconciliation_operation', call: Dry::Monads::Success(double('Application'))))
        end

        it 'successfully processes the enrollment with successful reconciliation' do
          result = subject.call(params)

          expect(result).to be_success
          expect(result.value!).to be_a(Hash)
          expect(result.value!).to have_key(:enrollment)
          expect(result.value!).to have_key(:reconciliation_result)
          expect(result.value![:reconciliation_result][:status]).to eq(:success)
        end
      end

      context 'when reconciliation is needed but fails' do
        before do
          allow(Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment).to receive(:new)
            .and_return(double('reconciliation_operation', call: Dry::Monads::Failure('Database connection failed')))
        end

        it 'fails the entire operation when reconciliation fails' do
          result = subject.call(params)

          expect(result).to be_failure
          expect(result.failure).to include('Reconciliation failed')
          expect(result.failure).to include('Database connection failed')
        end
      end

      context 'when enrollment does not qualify for reconciliation' do
        let(:unreconciliable_enrollment_state) { 'shopping' }
        let(:enrollment) do
          FactoryBot.create(:hbx_enrollment,
                            family: family,
                            product: product,
                            aasm_state: unreconciliable_enrollment_state)
        end

        it 'skips reconciliation and still builds family determination' do
          result = subject.call(params)

          expect(result).to be_success
          expect(result.value![:reconciliation_result][:status]).to eq(:skipped)
          expect(result.value![:reconciliation_result][:message]).to include('must be in one of these states')
        end
      end

      context 'when reconciliation raises an exception' do
        before do
          reconciliation_operation = double('reconciliation_operation')
          allow(Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment).to receive(:new)
            .and_return(reconciliation_operation)
          allow(reconciliation_operation).to receive(:call).and_raise(StandardError, 'Some error')
        end

        it 'fails the entire operation when reconciliation raises an exception' do
          result = subject.call(params)

          expect(result).to be_failure
          expect(result.failure).to include('Reconciliation error')
          expect(result.failure).to include('Some error')
        end
      end
    end

    context 'with missing GID' do
      let(:params) { {} }

      it 'returns failure with error message' do
        result = subject.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Missing enrollment GID')
      end
    end

    context 'with invalid GID' do
      let(:params) { { gid: 'invalid-gid' } }

      it 'returns failure when enrollment cannot be found' do
        result = subject.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Enrollment not found')
      end
    end

    context 'when family determination fails' do
      let(:params) { { gid: enrollment.to_global_id.to_s } }

      before do
        allow(Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment).to receive(:new)
          .and_return(double('reconciliation_operation', call: Dry::Monads::Success(double('Application'))))

        allow(Operations::Eligibilities::BuildFamilyDetermination).to receive(:new)
          .and_return(double('family_determination_operation', call: Dry::Monads::Failure('Determination failed')))
      end

      it 'returns failure when family determination fails' do
        result = subject.call(params)

        expect(result).to be_failure
        expect(result.failure).to include('Family determination failed')
      end
    end
  end

  describe '#reconcile_if_needed' do
    before do
      # Set up the instance variable that the method expects
      subject.instance_variable_set(:@enrollment, enrollment)
    end

    context 'when reconciliation succeeds' do
      before do
        allow(Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment).to receive(:new)
          .and_return(double('reconciliation_operation', call: Dry::Monads::Success(double('Application'))))
      end

      it 'returns success result as Success monad with structured hash' do
        result = subject.send(:reconcile_if_needed)

        expect(result).to be_success
        expect(result.value![:status]).to eq(:success)
        expect(result.value![:application]).to be_present
        expect(result.value![:message]).to eq('Reconciliation completed successfully')
      end
    end

    context 'when reconciliation fails' do
      before do
        allow(Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment).to receive(:new)
          .and_return(double('reconciliation_operation', call: Dry::Monads::Failure('System error')))
      end

      it 'returns failure result as Failure monad' do
        result = subject.send(:reconcile_if_needed)

        expect(result).to be_failure
        expect(result.failure).to include('Reconciliation failed')
        expect(result.failure).to include('System error')
      end
    end

    context 'when reconciliation raises exception' do
      before do
        reconciliation_operation = double('reconciliation_operation')
        allow(Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment).to receive(:new)
          .and_return(reconciliation_operation)
        allow(reconciliation_operation).to receive(:call).and_raise(StandardError, 'Some error')
      end

      it 'returns error result as Failure monad' do
        result = subject.send(:reconcile_if_needed)

        expect(result).to be_failure
        expect(result.failure).to include('Reconciliation error')
        expect(result.failure).to include('Some error')
      end
    end
  end

  describe '#reconcile_if_needed' do
    before do
      # Set up the instance variable that the method expects
      subject.instance_variable_set(:@enrollment, shopping_enrollment)
    end

    context 'when enrollment does not qualify for reconciliation' do
      let(:shopping_enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family,
                          product: product,
                          aasm_state: 'shopping')
      end

      it 'returns success with skipped status and structured hash' do
        result = subject.send(:reconcile_if_needed)

        expect(result).to be_success
        expect(result.value![:status]).to eq(:skipped)
        expect(result.value![:application]).to be_nil
        expect(result.value![:message]).to include('must be in one of these states')
      end
    end
  end

  describe '#enrollment_requires_reconciliation?' do
    context 'with valid enrollment state' do
      before do
        # Set up the instance variable that the method expects
        subject.instance_variable_set(:@enrollment, enrollment)
      end

      it 'returns true for reconciliation' do
        result = subject.send(:enrollment_requires_reconciliation?)

        expect(result).to eq([true, nil])
      end
    end

    context 'with invalid enrollment state' do
      let(:shopping_enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family,
                          product: product,
                          aasm_state: 'shopping')
      end

      before do
        subject.instance_variable_set(:@enrollment, shopping_enrollment)
      end

      it 'returns false with error message' do
        result = subject.send(:enrollment_requires_reconciliation?)

        expect(result[0]).to be false
        expect(result[1]).to include('must be in one of these states')
      end
    end

    context 'with application determination generation reason' do
      let(:determination_enrollment) do
        enrollment = FactoryBot.create(:hbx_enrollment,
                                       family: family,
                                       product: product,
                                       aasm_state: 'coverage_selected')
        enrollment.update_attribute(:generation_reason, :application_determination)
        enrollment
      end

      before do
        # Set up the instance variable that the method expects
        subject.instance_variable_set(:@enrollment, determination_enrollment)
      end

      it 'returns false for application determination enrollments' do
        result = subject.send(:enrollment_requires_reconciliation?)

        expect(result[0]).to be false
        expect(result[1]).to eq('Enrollments generated by application determinations do not require reconciliation')
      end
    end
  end
end
