# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility, type: :model, dbclean: :around_each do
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
                      family_member_id: family.primary_family_member.id,
                      is_ia_eligible: true)
  end

  let(:enrollment) do
    enrollment = FactoryBot.create(:hbx_enrollment,
                                   family: family,
                                   product: product,
                                   aasm_state: 'coverage_selected',
                                   hbx_id: 'TEST_HBX_ID',
                                   kind: 'individual',
                                   coverage_kind: 'health',
                                   applied_aptc_amount: 100.00)
    # Create enrollment member for the applicant so it shows up in active_enrollments
    FactoryBot.create(:hbx_enrollment_member,
                      hbx_enrollment: enrollment,
                      applicant_id: applicant.family_member_id,
                      is_subscriber: true)
    # Create workflow state transition to make it a new enrollment
    FactoryBot.create(:workflow_state_transition,
                      transitional: enrollment,
                      from_state: 'shopping',
                      to_state: 'coverage_selected')
    # Mock the enrollment to return true for APTC/CSR benefits
    allow(enrollment).to receive(:has_aptc_or_csr_applied?).and_return(true)
    enrollment
  end

  # active_applicant_enrollments should be pre-filtered to only include enrollments where the applicant is a member
  # This responsibility is handled at the applicant-level operation, not in BaseReconcileEligibility
  let(:active_applicant_enrollments) { [enrollment] }
  let(:aptc_csr_eligibility_double) { double('AptcCsrEligibility', present?: true, escalate_evidences_to_outstanding: true, downgrade_evidences_to_nrr: true) }

  let(:reconciler) { described_class.new }

  let(:valid_params) do
    {
      applicant: applicant,
      active_applicant_enrollments: active_applicant_enrollments,
      enrollment: enrollment
    }
  end

  before do
    allow(applicant).to receive(:aptc_csr_eligibility).and_return(aptc_csr_eligibility_double)
  end

  describe 'inheritance' do
    it 'inherits from BaseReconcileEligibility' do
      expect(described_class).to be < Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::BaseReconcileEligibility
    end
  end

  describe '#call' do
    before do
      allow(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr)
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
        expect(result.value![:eligibility]).to eq(aptc_csr_eligibility_double)
      end

      context 'when reconciliation is not needed' do
        before do
          allow(applicant).to receive(:aptc_csr_eligibility).and_return(nil)
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
      let(:tax_household_group) { double('TaxHouseholdGroup') }
      let(:tax_household) { double('TaxHousehold') }
      let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
      let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
      let(:mock_application) { double('Application', family: family) }

      before do
        allow(applicant).to receive(:application).and_return(mock_application)
        allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
        allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
        allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
        allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:exists?).and_return(true)
        allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)

        allow(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding)
          .and_raise(StandardError.new('APTC CSR error'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)

        expect(result).to be_failure
        expect(result.failure).to include('Reconciliation failed: APTC CSR error')
      end
    end
  end

  describe '#needs_reconciliation? (private method)' do
    context 'when APTC/CSR eligibility is present' do
      before do
        reconciler.call(valid_params) # Initialize instance variables
      end

      it 'returns true when all conditions are met' do
        expect(reconciler.send(:needs_reconciliation?)).to be true
      end

      context 'but applicant is not enrolled' do
        let(:active_applicant_enrollments) { [] }

        before do
          reconciler.call(valid_params.merge(active_applicant_enrollments: active_applicant_enrollments))
        end

        it 'returns false' do
          expect(reconciler.send(:needs_reconciliation?)).to be false
        end
      end

      context 'but enrollment is not a new enrollment' do
        let(:renewal_enrollment) do
          enrollment = FactoryBot.create(:hbx_enrollment,
                                         family: family,
                                         product: product,
                                         aasm_state: 'coverage_selected',
                                         hbx_id: 'RENEWAL_HBX_ID',
                                         kind: 'individual',
                                         coverage_kind: 'health',
                                         applied_aptc_amount: 100.00)
          # Create enrollment member for the applicant
          FactoryBot.create(:hbx_enrollment_member,
                            hbx_enrollment: enrollment,
                            applicant_id: applicant.family_member_id,
                            is_subscriber: true)
          # Create workflow state transition to make it a renewal (not new)
          FactoryBot.create(:workflow_state_transition,
                            transitional: enrollment,
                            from_state: 'auto_renewing',
                            to_state: 'coverage_selected')
          enrollment
        end

        before do
          reconciler.call(valid_params.merge(enrollment: renewal_enrollment, active_applicant_enrollments: [renewal_enrollment]))
        end

        it 'returns false' do
          expect(reconciler.send(:needs_reconciliation?)).to be false
        end
      end

      context 'but enrollment is not health coverage' do
        let(:dental_product) { FactoryBot.create(:benefit_markets_products_dental_products_dental_product) }
        let(:dental_enrollment) do
          enrollment = FactoryBot.create(:hbx_enrollment,
                                         family: family,
                                         product: dental_product,
                                         aasm_state: 'coverage_selected',
                                         hbx_id: 'DENTAL_HBX_ID',
                                         kind: 'individual',
                                         coverage_kind: 'dental')
          # Create enrollment member for the applicant
          FactoryBot.create(:hbx_enrollment_member,
                            hbx_enrollment: enrollment,
                            applicant_id: applicant.family_member_id,
                            is_subscriber: true)
          # Create workflow state transition to make it a new enrollment
          FactoryBot.create(:workflow_state_transition,
                            transitional: enrollment,
                            from_state: 'shopping',
                            to_state: 'coverage_selected')
          enrollment
        end

        before do
          reconciler.call(valid_params.merge(enrollment: dental_enrollment, active_applicant_enrollments: [dental_enrollment]))
        end

        it 'returns false' do
          expect(reconciler.send(:needs_reconciliation?)).to be false
        end
      end
    end

    context 'when APTC/CSR eligibility is not present' do
      before do
        allow(applicant).to receive(:aptc_csr_eligibility).and_return(double('Eligibility', present?: false))
        reconciler.call(valid_params) # Initialize instance variables
      end

      it 'returns false' do
        expect(reconciler.send(:needs_reconciliation?)).to be false
      end
    end

    context 'when APTC/CSR eligibility is nil' do
      before do
        allow(applicant).to receive(:aptc_csr_eligibility).and_return(nil)
        reconciler.call(valid_params) # Initialize instance variables
      end

      it 'returns false' do
        expect(reconciler.send(:needs_reconciliation?)).to be false
      end
    end
  end

  describe '#reconcile (private method)' do
    let(:action) { 'enrollment_purchase' }
    let(:message) { "Enrollment #{enrollment.hbx_id} has been purchased" }
    let(:tax_household_group) { double('TaxHouseholdGroup') }
    let(:tax_household) { double('TaxHousehold') }
    let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
    let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
    let(:mock_application) { double('Application', family: family) }

    before do
      allow(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr)

      allow(applicant).to receive(:application).and_return(mock_application)
      allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
      allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
      allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
      allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:exists?).and_return(true)
      allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)

      reconciler.call(valid_params) # Initialize instance variables
    end

    context 'when eligibility is applicable (applicant is IA eligible and enrolled with APTC/CSR)' do
      it 'calls escalate_evidences_to_outstanding on the APTC/CSR eligibility' do
        expect(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding).with(action, message)
        reconciler.send(:reconcile)
      end

      it 'does not call downgrade_evidences_to_nrr' do
        expect(aptc_csr_eligibility_double).not_to receive(:downgrade_evidences_to_nrr)
        reconciler.send(:reconcile)
      end
    end

    context 'when eligibility is not applicable' do
      before do
        # Make applicant not IA eligible
        allow(tax_household_member).to receive(:is_ia_eligible?).and_return(false)
        reconciler.call(valid_params) # Re-initialize with new conditions
      end

      it 'calls downgrade_evidences_to_nrr on the APTC/CSR eligibility' do
        expect(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr).with(action, message)
        reconciler.send(:reconcile)
      end

      it 'does not call escalate_evidences_to_outstanding' do
        expect(aptc_csr_eligibility_double).not_to receive(:escalate_evidences_to_outstanding)
        reconciler.send(:reconcile)
      end
    end
  end

  # Subclass-specific implementation tests
  describe '#eligibility (private method)' do
    before do
      reconciler.call(valid_params) # Initialize instance variables
    end

    it 'returns the APTC/CSR eligibility from the applicant' do
      expect(reconciler.send(:eligibility)).to eq(aptc_csr_eligibility_double)
    end

    it 'calls the aptc_csr_eligibility method on the applicant' do
      expect(applicant).to receive(:aptc_csr_eligibility).and_return(aptc_csr_eligibility_double)
      reconciler.send(:eligibility)
    end
  end

  describe '#applicable? (private method)' do
    let(:tax_household_group) { double('TaxHouseholdGroup') }
    let(:tax_household) { double('TaxHousehold') }
    let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
    let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
    let(:mock_application) { double('Application', family: family) }

    before do
      allow(applicant).to receive(:application).and_return(mock_application)
      allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
      allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
      allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
      allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:exists?).and_return(true)
      allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)

      reconciler.call(valid_params)
    end

    context 'when applicant is IA eligible and has APTC/CSR benefits' do
      it 'returns true' do
        expect(reconciler.send(:applicable?)).to be true
      end
    end

    context 'when applicant is not IA eligible' do
      before do
        allow(tax_household_member).to receive(:is_ia_eligible?).and_return(false)
        reconciler.call(valid_params) # Re-initialize with new conditions
      end

      it 'returns false' do
        expect(reconciler.send(:applicable?)).to be false
      end
    end

    context 'when applicant is IA eligible but has no APTC/CSR benefits' do
      let(:enrollment_without_aptc) do
        enrollment = FactoryBot.create(:hbx_enrollment,
                                       family: family,
                                       product: product,
                                       aasm_state: 'coverage_selected',
                                       hbx_id: 'NO_APTC_HBX_ID',
                                       kind: 'individual',
                                       coverage_kind: 'health',
                                       applied_aptc_amount: 0.00)
        FactoryBot.create(:hbx_enrollment_member,
                          hbx_enrollment: enrollment,
                          applicant_id: applicant.family_member_id,
                          is_subscriber: true)
        allow(enrollment).to receive(:has_aptc_or_csr_applied?).and_return(false)
        enrollment
      end

      before do
        reconciler.call(valid_params.merge(active_applicant_enrollments: [enrollment_without_aptc]))
      end

      it 'returns false' do
        expect(reconciler.send(:applicable?)).to be false
      end
    end

    context 'when applicant is not a FinancialAssistance::Applicant' do
      let(:individual_market_applicant) { double('IndividualMarket::Applicant', application: mock_application, family_member_id: 'other_id', aptc_csr_eligibility: nil) }

      before do
        allow(individual_market_applicant).to receive(:application).and_return(mock_application)
        allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(nil)
        reconciler.call(valid_params.merge(applicant: individual_market_applicant))
      end

      it 'returns false' do
        expect(reconciler.send(:applicable?)).to be false
      end
    end
  end

  describe '#applicant_ia_eligible? (private method)' do
    before do
      reconciler.call(valid_params)
    end

    context 'when navigating through family structure to find IA eligibility' do
      let(:tax_household_group) { double('TaxHouseholdGroup') }
      let(:tax_household) { double('TaxHousehold') }
      let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
      let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
      let(:mock_application) { double('Application', family: family) }

      before do
        allow(applicant).to receive(:application).and_return(mock_application)
        allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
        allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
        allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
        allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:exists?).and_return(true)
        allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)
      end

      it 'returns true when tax household member is IA eligible' do
        expect(reconciler.send(:applicant_ia_eligible?)).to be true
      end

      it 'navigates through family to find tax household group for enrollment year' do
        expect(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
        reconciler.send(:applicant_ia_eligible?)
      end
    end

    context 'when tax household member is not IA eligible' do
      let(:tax_household_group) { double('TaxHouseholdGroup') }
      let(:tax_household) { double('TaxHousehold') }
      let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
      let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: false) }
      let(:mock_application) { double('Application', family: family) }

      before do
        allow(applicant).to receive(:application).and_return(mock_application)
        allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
        allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
        allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
        allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:exists?).and_return(true)
        allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)
      end

      it 'returns false' do
        expect(reconciler.send(:applicant_ia_eligible?)).to be false
      end
    end

    context 'error handling scenarios' do
      context 'when tax household group is nil' do
        let(:mock_application) { double('Application', family: family) }

        before do
          allow(applicant).to receive(:application).and_return(mock_application)
          allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(nil)
        end

        it 'returns false due to nil check' do
          expect(reconciler.send(:applicant_ia_eligible?)).to be false
        end
      end

      context 'when tax household is not found for the applicant' do
        let(:tax_household_group) { double('TaxHouseholdGroup') }
        let(:tax_household) { double('TaxHousehold') }
        let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
        let(:mock_application) { double('Application', family: family) }

        before do
          allow(applicant).to receive(:application).and_return(mock_application)
          allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
          allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
          allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
          allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
          allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
          allow(tax_household_members_relation).to receive(:exists?).and_return(false)
        end

        it 'returns false when no matching tax household exists' do
          expect(reconciler.send(:applicant_ia_eligible?)).to be false
        end
      end

      context 'when tax household member record is nil' do
        let(:tax_household_group) { double('TaxHouseholdGroup') }
        let(:tax_household) { double('TaxHousehold') }
        let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
        let(:mock_application) { double('Application', family: family) }

        before do
          allow(applicant).to receive(:application).and_return(mock_application)
          allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
          allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
          allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
          allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
          allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
          allow(tax_household_members_relation).to receive(:exists?).and_return(true)
          allow(tax_household_members_relation).to receive(:first).and_return(nil)
        end

        it 'returns false due to nil check' do
          expect(reconciler.send(:applicant_ia_eligible?)).to be false
        end
      end

      context 'when family is nil' do
        let(:mock_application) { double('Application', family: nil) }

        before do
          allow(applicant).to receive(:application).and_return(mock_application)
        end

        it 'returns false due to nil check' do
          expect(reconciler.send(:applicant_ia_eligible?)).to be false
        end
      end

      context 'when applicant application is nil' do
        before do
          allow(applicant).to receive(:application).and_return(nil)
        end

        it 'returns false due to nil check' do
          expect(reconciler.send(:applicant_ia_eligible?)).to be false
        end
      end
    end

    context 'when multiple tax households exist' do
      let(:tax_household_group) { double('TaxHouseholdGroup') }
      let(:other_tax_household) { double('OtherTaxHousehold') }
      let(:correct_tax_household) { double('CorrectTaxHousehold') }
      let(:other_tax_household_members_relation) { double('OtherTaxHouseholdMembers') }
      let(:correct_tax_household_members_relation) { double('CorrectTaxHouseholdMembers') }
      let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
      let(:mock_application) { double('Application', family: family) }

      before do
        allow(applicant).to receive(:application).and_return(mock_application)
        allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
        allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
        allow(tax_household_group).to receive(:tax_households).and_return([other_tax_household, correct_tax_household])

        allow(other_tax_household).to receive(:tax_household_members).and_return(other_tax_household_members_relation)
        allow(other_tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(other_tax_household_members_relation)
        allow(other_tax_household_members_relation).to receive(:exists?).and_return(false)

        allow(correct_tax_household).to receive(:tax_household_members).and_return(correct_tax_household_members_relation)
        allow(correct_tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(correct_tax_household_members_relation)
        allow(correct_tax_household_members_relation).to receive(:exists?).and_return(true)
        allow(correct_tax_household_members_relation).to receive(:first).and_return(tax_household_member)
      end

      it 'finds the correct tax household containing the applicant' do
        expect(reconciler.send(:applicant_ia_eligible?)).to be true
      end
    end
  end

  describe '#applicant_ia_enrolled? (private method)' do
    before do
      reconciler.call(valid_params)
    end

    context 'when applicant has enrollments with APTC/CSR benefits' do
      it 'returns true' do
        expect(reconciler.send(:applicant_ia_enrolled?)).to be true
      end
    end

    context 'when applicant has enrollments without APTC/CSR benefits' do
      let(:enrollment_without_aptc) do
        enrollment = FactoryBot.create(:hbx_enrollment,
                                       family: family,
                                       product: product,
                                       aasm_state: 'coverage_selected',
                                       applied_aptc_amount: 0.00)
        allow(enrollment).to receive(:has_aptc_or_csr_applied?).and_return(false)
        enrollment
      end

      before do
        reconciler.call(valid_params.merge(active_applicant_enrollments: [enrollment_without_aptc]))
      end

      it 'returns false' do
        expect(reconciler.send(:applicant_ia_enrolled?)).to be false
      end
    end

    context 'when applicant has no active enrollments' do
      before do
        reconciler.call(valid_params.merge(active_applicant_enrollments: []))
      end

      it 'returns false' do
        expect(reconciler.send(:applicant_ia_enrolled?)).to be false
      end
    end
  end

  describe 'business logic differences from Individual Market reconciler' do
    it 'has more restrictive reconciliation requirements' do
      dental_product = FactoryBot.create(:benefit_markets_products_dental_products_dental_product)
      dental_enrollment = FactoryBot.create(:hbx_enrollment,
                                            family: family,
                                            product: dental_product,
                                            coverage_kind: 'dental')

      dental_params = valid_params.merge(enrollment: dental_enrollment)

      result = reconciler.call(dental_params)
      expect(result).to be_success
      expect(result.value![:reconciled]).to be false
    end

    it 'has more complex applicability logic' do
      enrollment_without_aptc = FactoryBot.create(:hbx_enrollment,
                                                  family: family,
                                                  product: product,
                                                  applied_aptc_amount: 0.00)
      allow(enrollment_without_aptc).to receive(:has_aptc_or_csr_applied?).and_return(false)

      allow(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr)
      reconciler.call(valid_params.merge(active_applicant_enrollments: [enrollment_without_aptc]))

      expect(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr)
      reconciler.send(:reconcile)
    end
  end

  describe 'integration scenarios' do
    let(:tax_household_group) { double('TaxHouseholdGroup') }
    let(:tax_household) { double('TaxHousehold') }
    let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
    let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
    let(:mock_application) { double('Application', family: family) }

    before do
      allow(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding)
      allow(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr)

      allow(applicant).to receive(:application).and_return(mock_application)
      allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
      allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
      allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
      allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:exists?).and_return(true)
      allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)
    end

    context 'when reconciling after new health enrollment with APTC' do
      it 'requires eligibility evidences for IA eligible member with APTC benefits' do
        expect(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding).with(
          'enrollment_purchase',
          "Enrollment #{enrollment.hbx_id} has been purchased"
        )

        result = reconciler.call(valid_params)
        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
      end
    end

    context 'when reconciling after dental enrollment' do
      let(:dental_product) { FactoryBot.create(:benefit_markets_products_dental_products_dental_product) }
      let(:dental_enrollment) do
        FactoryBot.create(:hbx_enrollment,
                          family: family,
                          product: dental_product,
                          coverage_kind: 'dental')
      end

      it 'does not reconcile for dental coverage' do
        result = reconciler.call(valid_params.merge(enrollment: dental_enrollment))
        expect(result).to be_success
        expect(result.value![:reconciled]).to be false
        expect(result.value![:reason]).to eq('No reconciliation needed')
      end
    end

    context 'when reconciling for non-IA eligible member' do
      before do
        allow(tax_household_member).to receive(:is_ia_eligible?).and_return(false)
      end

      it 'waives eligibility evidences for non-IA eligible member' do
        expect(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr).with(
          'enrollment_purchase',
          "Enrollment #{enrollment.hbx_id} has been purchased"
        )

        result = reconciler.call(valid_params)
        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
      end
    end
  end

  describe 'integration with enrollment context' do
    let(:hbx_id) { 'TEST_APTC_CSR_HBX_ID_123' }
    let(:tax_household_group) { double('TaxHouseholdGroup') }
    let(:tax_household) { double('TaxHousehold') }
    let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
    let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
    let(:mock_application) { double('Application', family: family) }
    let(:enrollment_with_hbx_id) do
      enrollment = FactoryBot.create(:hbx_enrollment,
                                     family: family,
                                     product: product,
                                     aasm_state: 'coverage_selected',
                                     hbx_id: hbx_id,
                                     kind: 'individual',
                                     coverage_kind: 'health',
                                     applied_aptc_amount: 150.00)
      FactoryBot.create(:workflow_state_transition,
                        transitional: enrollment,
                        from_state: 'shopping',
                        to_state: 'coverage_selected')
      enrollment
    end

    before do
      allow(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding)

      allow(applicant).to receive(:application).and_return(mock_application)
      allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
      allow(family).to receive(:active_thhg).with(enrollment_with_hbx_id.effective_on.year).and_return(tax_household_group)
      allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
      allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
      allow(tax_household_members_relation).to receive(:exists?).and_return(true)
      allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)
    end

    it 'uses correct enrollment context in adjustment messages' do
      expected_message = "Enrollment #{hbx_id} has been purchased"
      expected_action = 'enrollment_purchase'

      expect(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding).with(expected_action, expected_message)

      reconciler.call(valid_params.merge(enrollment: enrollment_with_hbx_id))
    end
  end

  describe 'error handling' do
    context 'when APTC/CSR eligibility method is not available' do
      before do
        allow(applicant).to receive(:aptc_csr_eligibility).and_raise(NoMethodError.new('Method not found'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)
        expect(result).to be_failure
        expect(result.failure).to include('Reconciliation failed: Method not found')
      end
    end

    context 'when eligibility operations raise errors' do
      let(:tax_household_group) { double('TaxHouseholdGroup') }
      let(:tax_household) { double('TaxHousehold') }
      let(:tax_household_members_relation) { double('TaxHouseholdMembers') }
      let(:tax_household_member) { double('TaxHouseholdMember', is_ia_eligible?: true) }
      let(:mock_application) { double('Application', family: family) }

      before do
        allow(applicant).to receive(:application).and_return(mock_application)
        allow(applicant).to receive(:family_member_id).and_return('test_family_member_id')
        allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(tax_household_group)
        allow(tax_household_group).to receive(:tax_households).and_return([tax_household])
        allow(tax_household).to receive(:tax_household_members).and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:where).with(applicant_id: 'test_family_member_id').and_return(tax_household_members_relation)
        allow(tax_household_members_relation).to receive(:exists?).and_return(true)
        allow(tax_household_members_relation).to receive(:first).and_return(tax_household_member)

        allow(aptc_csr_eligibility_double).to receive(:escalate_evidences_to_outstanding).and_raise(StandardError.new('APTC CSR evidence error'))
      end

      it 'returns failure with error message' do
        result = reconciler.call(valid_params)
        expect(result).to be_failure
        expect(result.failure).to eq('Reconciliation failed: APTC CSR evidence error')
      end
    end

    context 'when IA eligibility check returns false due to nil values' do
      let(:mock_application) { double('Application', family: family) }

      before do
        allow(applicant).to receive(:application).and_return(mock_application)
        allow(family).to receive(:active_thhg).with(enrollment.effective_on.year).and_return(nil)
        allow(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr)
      end

      it 'treats nil as not IA eligible and downgrades evidences' do
        result = reconciler.call(valid_params)
        expect(result).to be_success
        expect(result.value![:reconciled]).to be true
      end

      it 'calls downgrade_evidences_to_nrr due to IA ineligibility' do
        expect(aptc_csr_eligibility_double).to receive(:downgrade_evidences_to_nrr)
        reconciler.call(valid_params)
      end
    end
  end
end
