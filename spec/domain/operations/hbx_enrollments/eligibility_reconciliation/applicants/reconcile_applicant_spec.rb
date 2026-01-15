# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::HbxEnrollments::EligibilityReconciliation::Applicants::ReconcileApplicant, type: :model, dbclean: :around_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :silver) }

  let(:enrollment) do
    enrollment = FactoryBot.create(:hbx_enrollment,
                                   family: family,
                                   product: product,
                                   aasm_state: 'coverage_selected',
                                   hbx_id: 'test-enrollment-123')
    # Create enrollment member for the applicant so it gets filtered correctly
    FactoryBot.create(:hbx_enrollment_member,
                      hbx_enrollment: enrollment,
                      applicant_id: applicant.family_member_id,
                      is_subscriber: true)
    enrollment
  end

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

  let(:active_enrollments) { HbxEnrollment.where(id: enrollment.id) }

  let(:reconciler) { described_class.new }

  let(:valid_params) do
    {
      applicant: applicant,
      enrollment: enrollment,
      active_enrollments: active_enrollments
    }
  end

  describe '#call' do
    context 'with valid parameters' do
      let(:aptc_reconciler_double) { instance_double(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility) }
      let(:individual_reconciler_double) { instance_double(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileIndividualMarketEligibility) }

      before do
        allow(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility)
          .to receive(:new).and_return(aptc_reconciler_double)
        allow(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileIndividualMarketEligibility)
          .to receive(:new).and_return(individual_reconciler_double)

        allow(aptc_reconciler_double).to receive(:call).and_return(Dry::Monads::Success({}))
        allow(individual_reconciler_double).to receive(:call).and_return(Dry::Monads::Success({}))
      end

      it 'succeeds and calls both eligibility reconcilers' do
        result = reconciler.call(valid_params)

        expect(result).to be_success
        expect(result.value!).to be_a(Hash)
        expect(result.value!.keys).to contain_exactly(:aptc_csr_eligibility, :individual_market_eligibility)

        # Verify reconcilers are called with filtered active_applicant_enrollments (where applicant is a member)
        expect(aptc_reconciler_double).to have_received(:call).with(
          applicant: applicant,
          enrollment: enrollment,
          active_applicant_enrollments: [enrollment]  # Should be filtered to only include enrollments where applicant is a member
        )
        expect(individual_reconciler_double).to have_received(:call).with(
          applicant: applicant,
          enrollment: enrollment,
          active_applicant_enrollments: [enrollment]  # Should be filtered to only include enrollments where applicant is a member
        )
      end

      it 'returns results from each reconciler in a hash' do
        aptc_result = { reconciled: true, eligibility: 'aptc_eligibility' }
        individual_result = { reconciled: false, reason: 'No reconciliation needed' }

        allow(aptc_reconciler_double).to receive(:call).and_return(Dry::Monads::Success(aptc_result))
        allow(individual_reconciler_double).to receive(:call).and_return(Dry::Monads::Success(individual_result))

        result = reconciler.call(valid_params)

        expect(result).to be_success
        expect(result.value![:aptc_csr_eligibility]).to eq(aptc_result)
        expect(result.value![:individual_market_eligibility]).to eq(individual_result)
      end

      context 'when individual market reconciler fails' do
        before do
          allow(individual_reconciler_double).to receive(:call)
            .and_return(Dry::Monads::Failure('Individual market reconciliation failed'))
        end

        it 'returns failure with the error message' do
          result = reconciler.call(valid_params)

          expect(result).to be_failure
          expect(result.failure).to eq('Individual market reconciliation failed')
        end

        it 'does not call the APTC/CSR reconciler' do
          reconciler.call(valid_params)

          expect(aptc_reconciler_double).not_to have_received(:call)
        end
      end

      context 'when APTC/CSR reconciler fails' do
        before do
          allow(aptc_reconciler_double).to receive(:call)
            .and_return(Dry::Monads::Failure('APTC reconciliation failed'))
        end

        it 'returns failure with the error message' do
          result = reconciler.call(valid_params)

          expect(result).to be_failure
          expect(result.failure).to eq('APTC reconciliation failed')
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

      it 'fails when active_enrollments is missing' do
        params = valid_params.except(:active_enrollments)
        result = reconciler.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Missing active_enrollments')
      end

      it 'fails when applicant is not the correct type' do
        params = valid_params.merge(applicant: 'invalid_applicant')
        result = reconciler.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Invalid applicant object')
      end

      it 'fails when enrollment is not the correct type' do
        params = valid_params.merge(enrollment: 'invalid_enrollment')
        result = reconciler.call(params)

        expect(result).to be_failure
        expect(result.failure).to eq('Invalid enrollment object')
      end
    end

    context 'when reconciliation raises an error' do
      let(:aptc_reconciler_double) { instance_double(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility) }

      before do
        allow(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility)
          .to receive(:new).and_return(aptc_reconciler_double)
        allow(aptc_reconciler_double).to receive(:call)
          .and_raise(StandardError.new('Unexpected error'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)

        expect(result).to be_failure
        expect(result.failure).to include('Failed to reconcile eligibilities: Unexpected error')
      end
    end
  end

  describe 'enrollment filtering behavior' do
    let(:other_person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:other_family_member) { FactoryBot.create(:family_member, family: family, person: other_person) }

    let!(:enrollment_with_applicant) do
      enr = FactoryBot.create(:hbx_enrollment, family: family, product: product, hbx_id: 'with-applicant')
      FactoryBot.create(:hbx_enrollment_member,
                        hbx_enrollment: enr,
                        applicant_id: applicant.family_member_id,
                        is_subscriber: true)
      enr
    end

    let!(:enrollment_without_applicant) do
      enr = FactoryBot.create(:hbx_enrollment, family: family, product: product, hbx_id: 'without-applicant')
      FactoryBot.create(:hbx_enrollment_member,
                        hbx_enrollment: enr,
                        applicant_id: other_family_member.id,
                        is_subscriber: true)
      enr
    end

    let(:mixed_enrollments) { HbxEnrollment.where(:id.in => [enrollment_with_applicant.id, enrollment_without_applicant.id]) }
    let(:aptc_reconciler_double) { instance_double(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility) }
    let(:individual_reconciler_double) { instance_double(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileIndividualMarketEligibility) }

    before do
      allow(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility)
        .to receive(:new).and_return(aptc_reconciler_double)
      allow(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileIndividualMarketEligibility)
        .to receive(:new).and_return(individual_reconciler_double)

      allow(aptc_reconciler_double).to receive(:call).and_return(Dry::Monads::Success({}))
      allow(individual_reconciler_double).to receive(:call).and_return(Dry::Monads::Success({}))
    end

    it 'filters active_enrollments to only include those where applicant is a member' do
      params = valid_params.merge(active_enrollments: mixed_enrollments)

      result = reconciler.call(params)

      expect(result).to be_success

      # Verify that only the enrollment with the applicant is passed to reconcilers
      expect(aptc_reconciler_double).to have_received(:call).with(
        applicant: applicant,
        enrollment: enrollment,
        active_applicant_enrollments: [enrollment_with_applicant]  # Only the enrollment where applicant is a member
      )
      expect(individual_reconciler_double).to have_received(:call).with(
        applicant: applicant,
        enrollment: enrollment,
        active_applicant_enrollments: [enrollment_with_applicant]  # Only the enrollment where applicant is a member
      )
    end

    it 'passes empty array when no enrollments include the applicant' do
      params = valid_params.merge(active_enrollments: HbxEnrollment.where(id: enrollment_without_applicant.id))

      result = reconciler.call(params)

      expect(result).to be_success

      # Verify that empty array is passed when applicant is not in any enrollments
      expect(aptc_reconciler_double).to have_received(:call).with(
        applicant: applicant,
        enrollment: enrollment,
        active_applicant_enrollments: []  # No enrollments where applicant is a member
      )
      expect(individual_reconciler_double).to have_received(:call).with(
        applicant: applicant,
        enrollment: enrollment,
        active_applicant_enrollments: []  # No enrollments where applicant is a member
      )
    end
  end

  describe 'private methods' do
    describe '#filter_active_applicant_enrollments' do
      let(:other_person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:other_family_member) { FactoryBot.create(:family_member, family: family, person: other_person) }

      let(:enrollment_with_applicant) do
        enr = FactoryBot.create(:hbx_enrollment, family: family, product: product)
        FactoryBot.create(:hbx_enrollment_member,
                          hbx_enrollment: enr,
                          applicant_id: applicant.family_member_id,
                          is_subscriber: true)
        enr
      end

      let(:enrollment_without_applicant) do
        enr = FactoryBot.create(:hbx_enrollment, family: family, product: product)
        FactoryBot.create(:hbx_enrollment_member,
                          hbx_enrollment: enr,
                          applicant_id: other_family_member.id,
                          is_subscriber: true)
        enr
      end

      before do
        reconciler.send(:validate, valid_params.merge(active_enrollments: HbxEnrollment.where(:id.in => [enrollment_with_applicant.id, enrollment_without_applicant.id])))
      end

      it 'returns only enrollments where applicant is a member' do
        result = reconciler.send(:filter_active_applicant_enrollments, :aptc_csr_eligibility)

        expect(result).to include(enrollment_with_applicant)
        expect(result).not_to include(enrollment_without_applicant)
        expect(result.length).to eq(1)
      end

      it 'returns empty array when applicant is not in any enrollments' do
        reconciler.send(:validate, valid_params.merge(active_enrollments: HbxEnrollment.where(id: enrollment_without_applicant.id)))

        result = reconciler.send(:filter_active_applicant_enrollments, :individual_market_eligibility)

        expect(result).to be_empty
      end
    end

    describe '#reconciler_class_for' do
      it 'returns ReconcileAptcCsrEligibility for :aptc_csr' do
        reconciler.send(:validate, valid_params)
        result = reconciler.send(:reconciler_class_for, :aptc_csr_eligibility)

        expect(result).to eq(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility)
      end

      it 'returns ReconcileIndividualMarketEligibility for :individual_market' do
        reconciler.send(:validate, valid_params)
        result = reconciler.send(:reconciler_class_for, :individual_market_eligibility)

        expect(result).to eq(Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileIndividualMarketEligibility)
      end
    end

    describe '#reconcile_eligibility_type' do
      it 'raises ArgumentError for unknown eligibility type' do
        reconciler.send(:validate, valid_params)

        expect do
          reconciler.send(:reconcile_eligibility_type, :unknown_type, [])
        end.to raise_error(ArgumentError, 'Unknown eligibility type: unknown_type')
      end
    end
  end

  describe 'constants' do
    it 'defines expected eligibility types' do
      expect(described_class::ELIGIBILITY_KEYS).to include(:individual_market_eligibility, :aptc_csr_eligibility)
    end
  end
end
