# frozen_string_literal: true

module Operations
  module HbxEnrollments
    module EligibilityReconciliation
      module Eligibilities
        # Reconciles Individual Market eligibility with enrollment status
        #
        # Individual Market eligibility is:
        # 1. Reconciled when the eligibility is present
        # 2. Applicable when the applicant is enrolled in active coverage.
        #
        # @example Usage
        #   result = ReconcileIndividualMarketEligibility.new.call({
        #     applicant: applicant,
        #     active_enrollments: enrollments,
        #     enrollment: enrollment
        #   })
        #
        # @see BaseReconcileEligibility
        # @see ReconcileAptcCsrEligibility
        class ReconcileIndividualMarketEligibility < Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::BaseReconcileEligibility

          private

          # Gets the Individual Market eligibility from the applicant
          #
          # @return [Object] The Individual Market eligibility object
          def eligibility
            @applicant.individual_market_eligibility
          end

          # Determines if Individual Market eligibility should be escalated or downgraded
          #
          # Individual Market eligibility is applicable (should be escalated) simply based on applicant enrollment membership alone
          #
          # @return [Boolean] True if eligibility should be escalated, false if downgraded
          def applicable?
            applicant_enrolled?
          end
        end
      end
    end
  end
end
