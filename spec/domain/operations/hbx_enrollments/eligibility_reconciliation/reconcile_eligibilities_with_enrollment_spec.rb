# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::HbxEnrollments::EligibilityReconciliation::ReconcileEligibilitiesWithEnrollment, :type => :model, dbclean: :around_each do
  include Dry::Monads[:result]

  let(:operation) { described_class.new }

  describe '#call validation failures' do
    context 'when enrollment parameter is missing' do
      it 'returns failure with missing enrollment message' do
        result = operation.call({})
        expect(result).to be_failure
        expect(result.failure).to eq('Missing enrollment')
      end

      it 'returns failure when enrollment is nil' do
        result = operation.call({enrollment: nil})
        expect(result).to be_failure
        expect(result.failure).to eq('Missing enrollment')
      end
    end

    context 'when enrollment parameter is invalid' do
      it 'returns failure when enrollment is not an HbxEnrollment object' do
        result = operation.call({enrollment: 'invalid-enrollment'})
        expect(result).to be_failure
        expect(result.failure).to eq('Invalid enrollment object')
      end
    end

    context 'when enrollment has no related application' do
      let(:person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :silver) }
      let(:enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family,
                          product: product,
                          aasm_state: 'coverage_selected')
      end

      before do
        allow(TaxHouseholdEnrollment).to receive(:find_by).and_return(nil)
        allow(family).to receive(:latest_determined_application_for_year).and_return(nil)
      end

      it 'returns failure with missing application message' do
        result = operation.call({enrollment: enrollment})
        expect(result).to be_failure
        expect(result.failure).to eq('Missing application')
      end
    end
  end
  describe '#call success scenarios' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :silver) }

    let(:enrollment) do
      FactoryBot.create(:hbx_enrollment,
                        family: family,
                        product: product,
                        aasm_state: 'coverage_selected')
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

    let(:reconciler_double) { double('ReconcileApplicant') }

    before do
      allow(enrollment).to receive(:related_application).and_return(application)

      allow(family).to receive_message_chain(:hbx_enrollments, :enrolled_and_renewing, :by_health, :by_year)
        .and_return([enrollment])

      allow(Operations::HbxEnrollments::EligibilityReconciliation::Applicants::ReconcileApplicant)
        .to receive(:new).and_return(reconciler_double)
      allow(reconciler_double).to receive(:call).and_return(Success('reconciled'))

      applicant
    end

    context 'when enrollment has a related application' do
      it 'successfully reconciles eligibilities and returns the application' do
        result = operation.call({enrollment: enrollment})

        expect(result).to be_success
        expect(result.success).to eq(application)
      end

      it 'calls ReconcileApplicant for each applicant' do
        expect(Operations::HbxEnrollments::EligibilityReconciliation::Applicants::ReconcileApplicant)
          .to receive(:new)
          .and_return(reconciler_double)

        expect(reconciler_double).to receive(:call)
          .with(hash_including(applicant: applicant, enrollment: enrollment, active_enrollments: [enrollment]))
          .and_return(Success('reconciled'))

        operation.call({enrollment: enrollment})
      end
    end

    context 'when application save fails' do
      before do
        allow(application).to receive(:save!).and_raise(StandardError.new('Database error'))
      end

      it 'returns failure with save error message' do
        result = operation.call({enrollment: enrollment})

        expect(result).to be_failure
        expect(result.failure).to eq('Failed to save application: Database error')
      end
    end

    context 'when applicant reconciliation fails' do
      before do
        allow(reconciler_double).to receive(:call).and_return(Failure('Reconciler error'))
      end

      it 'returns failure with reconciliation error message' do
        result = operation.call({enrollment: enrollment})

        expect(result).to be_failure
        expect(result.failure).to eq('Reconciler error')
      end
    end

    context 'with multiple applicants' do
      let(:dependent) { FactoryBot.create(:person, :with_consumer_role) }
      let(:dependent_member) { FactoryBot.create(:family_member, family: family, person: dependent) }

      let(:dependent_applicant) do
        FactoryBot.create(:financial_assistance_applicant,
                          application: application,
                          is_primary_applicant: false,
                          family_member_id: dependent_member.id)
      end

      before do
        dependent_applicant
      end

      it 'calls ReconcileApplicant for each applicant' do
        expect(Operations::HbxEnrollments::EligibilityReconciliation::Applicants::ReconcileApplicant)
          .to receive(:new)
          .twice
          .and_return(reconciler_double)

        expect(reconciler_double).to receive(:call)
          .with(hash_including(applicant: applicant, enrollment: enrollment, active_enrollments: [enrollment]))
          .and_return(Success('reconciled'))

        expect(reconciler_double).to receive(:call)
          .with(hash_including(applicant: dependent_applicant, enrollment: enrollment, active_enrollments: [enrollment]))
          .and_return(Success('reconciled'))

        result = operation.call({enrollment: enrollment})
        expect(result).to be_success
      end
    end

    context 'when application has no applicants' do
      before do
        application.applicants.delete_all
      end

      it 'still succeeds but does not call ReconcileApplicant' do
        expect(Operations::HbxEnrollments::EligibilityReconciliation::Applicants::ReconcileApplicant)
          .not_to receive(:new)

        result = operation.call({enrollment: enrollment})
        expect(result).to be_success
        expect(result.success).to eq(application)
      end
    end

    context 'when fetch_active_enrollments fails' do
      before do
        allow(enrollment).to receive_message_chain(:family, :hbx_enrollments, :enrolled_and_renewing, :by_health, :by_year)
          .and_raise(StandardError.new('Database connection failed'))
      end

      it 'returns failure with fetch error message' do
        result = operation.call({enrollment: enrollment})

        expect(result).to be_failure
        expect(result.failure).to eq('Failed to update applicants: Database connection failed')
      end
    end
  end

  describe 'private method coverage' do
    describe '#fetch_active_enrollments' do
      let(:person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, :silver) }
      let(:enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family,
                          product: product,
                          aasm_state: 'coverage_selected',
                          effective_on: Date.new(2025, 1, 1))
      end

      it 'fetches active health enrollments for the enrollment year' do
        operation.instance_variable_set(:@enrollment, enrollment)

        expect(family.hbx_enrollments).to receive(:enrolled_and_renewing).and_return(family.hbx_enrollments)
        expect(family.hbx_enrollments).to receive(:by_health).and_return(family.hbx_enrollments)
        expect(family.hbx_enrollments).to receive(:by_year).with(2025).and_return([enrollment])

        result = operation.send(:fetch_active_enrollments)
        expect(result).to eq([enrollment])
      end
    end

    describe '#save_application' do
      let(:application) { double('Application') }

      it 'calls save! on application and returns Success with application' do
        expect(application).to receive(:save!)

        result = operation.send(:save_application, application)
        expect(result).to be_success
        expect(result.success).to eq(application)
      end

      it 'handles save errors and returns Failure' do
        expect(application).to receive(:save!).and_raise(StandardError.new('Validation failed'))

        result = operation.send(:save_application, application)
        expect(result).to be_failure
        expect(result.failure).to eq('Failed to save application: Validation failed')
      end
    end

    describe '#validate' do
      it 'returns Success when enrollment is present and valid' do
        enrollment = double('HbxEnrollment')
        allow(enrollment).to receive(:is_a?).with(HbxEnrollment).and_return(true)

        result = operation.send(:validate, {enrollment: enrollment})
        expect(result).to be_success
        expect(result.success).to eq(enrollment)
      end

      it 'returns Failure when enrollment is missing' do
        result = operation.send(:validate, {})
        expect(result).to be_failure
        expect(result.failure).to eq('Missing enrollment')
      end

      it 'returns Failure when enrollment is nil' do
        result = operation.send(:validate, {enrollment: nil})
        expect(result).to be_failure
        expect(result.failure).to eq('Missing enrollment')
      end

      it 'returns Failure when enrollment is not an HbxEnrollment' do
        result = operation.send(:validate, {enrollment: 'not_an_enrollment'})
        expect(result).to be_failure
        expect(result.failure).to eq('Invalid enrollment object')
      end
    end

    describe '#fetch_related_application' do
      let(:enrollment) { double('HbxEnrollment') }
      let(:family) { double('Family') }
      let(:application) { double('Application') }

      before do
        operation.instance_variable_set(:@enrollment, enrollment)
        allow(enrollment).to receive(:id).and_return('enrollment_id')
        allow(enrollment).to receive(:family).and_return(family)
        allow(enrollment).to receive(:effective_on).and_return(Date.new(2025, 1, 1))
      end

      it 'returns Success when application found via tax household' do
        allow(enrollment).to receive(:related_application).and_return(application)

        result = operation.send(:fetch_related_application)
        expect(result).to be_success
        expect(result.success).to eq(application)
      end

      it 'returns Success when application found via latest determined application fallback' do
        allow(enrollment).to receive(:related_application).and_return(application)

        result = operation.send(:fetch_related_application)
        expect(result).to be_success
        expect(result.success).to eq(application)
      end

      it 'returns Failure when no application exists' do
        allow(enrollment).to receive(:related_application).and_return(nil)

        result = operation.send(:fetch_related_application)
        expect(result).to be_failure
        expect(result.failure).to eq('Missing application')
      end
    end
  end
end
