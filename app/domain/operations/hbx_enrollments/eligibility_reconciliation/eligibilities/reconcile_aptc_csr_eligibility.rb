# frozen_string_literal: true

module Operations
  module HbxEnrollments
    module EligibilityReconciliation
      module Eligibilities
        # Reconciles APTC/CSR eligibility with enrollment status
        #
        # APTC/CSR eligibility is:
        # 1. Reconciled when the reconciling enrollment is a new health enrollment and the applicant has active enrollment
        # 2. Applicable when the applicant is IA eligible and has active enrollment with APTC/CSR applied
        #
        # @see BaseReconcileEligibility
        class ReconcileAptcCsrEligibility < Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::BaseReconcileEligibility

          private

          # Gets the APTC/CSR eligibility from the applicant
          #
          # @return [Object] The APTC/CSR eligibility object
          def eligibility
            @applicant.aptc_csr_eligibility
          end

          # Determines if APTC/CSR eligibility should be reconciled
          #
          # APTC/CSR eligibility reconciliation is more restrictive than Individual Market
          # and requires all of the following conditions:
          # 1. Base eligibility exists (from parent class)
          # 2. Applicant is enrolled in active enrollments
          # 3. Enrollment change being reconciled is a new enrollment (not a renewal) event
          # 4. The enrollment is for health coverage (not dental)
          #
          # @return [Boolean] True if APTC/CSR eligibility should be reconciled
          def needs_reconciliation?
            return false unless super

            # NOTE: there very well may be a race condition here in regards to the `new_enrollment?` check.
            # `new_enrollment?` relies on the `workflow_state_transitions` which may have not been built when
            # we are reconciling evidences. This needs further investigation.
            # @see HbxEnrollment#new_enrollment?
            # @see HbxEnrollment#generate_enrollment_saved_event
            # @see Subscribers::EnrollmentSubscriber
            # Furthermore, I'm not sure why the `new_enrollment?` check is necessary at all.
            applicant_enrolled? && @enrollment.new_enrollment? && @enrollment.health?
          end

          # Determines if APTC/CSR eligibility should be escalated or downgraded
          #
          # APTC/CSR eligibility is applicable (should be escalated) when both:
          # 1. Applicant is Individual Assistance (IA) eligible
          # 2. Applicant has APTC or CSR benefits applied in active enrollments
          #
          # @return [Boolean] True if eligibility should be escalated, false if should be downgraded
          def applicable?
            applicant_ia_eligible? && applicant_ia_enrolled?
          end

          # Checks if the applicant has been marked as Insurance Assistance eligible
          #
          # Navigates through the family structure to locate the applicant's tax household
          # member record and checks their IA eligibility status.
          #
          # @return [Boolean] True if applicant is IA eligible, false if not eligible or if any errors occur
          def applicant_ia_eligible?
            application = @applicant.application
            return false unless application

            family = application.family
            return false unless family

            tax_household_group = family.active_thhg(@enrollment.effective_on.year)
            return false unless tax_household_group

            tax_household = tax_household_group.tax_households.detect { |th| th.tax_household_members.where(applicant_id: @applicant.family_member_id).exists? }
            return false unless tax_household

            tax_household_member = tax_household.tax_household_members.where(applicant_id: @applicant.family_member_id).first
            return false unless tax_household_member

            tax_household_member.is_ia_eligible?
          end

          # Checks if the applicant has APTC or CSR benefits in any active enrollments
          #
          # Searches through active enrollments where the applicant is a member to find
          # ones that have APTC or CSR benefits applied.
          #
          # @return [Boolean] True if applicant has APTC/CSR benefits, false otherwise
          def applicant_ia_enrolled?
            @active_applicant_enrollments.any?(&:has_aptc_or_csr_applied?)
          end
        end
      end
    end
  end
end
