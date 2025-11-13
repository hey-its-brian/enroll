# frozen_string_literal: true

module Operations
  module HbxEnrollments
    module EligibilityReconciliation
      module Eligibilities
        # Base class for reconciling eligibilities with enrollment changes
        #
        # Manages the synchronization of an eligibility with enrollment changes by determining:
        # - Whether the eligibility should be reconciled (`needs_reconciliation?`)
        # - Whether the eligibility is applicable (`applicable?`)
        #
        # Eligibilities requiring reconciliation are adjusted (escalated or downgraded) based on their applicability.
        #
        # @abstract Subclasses must implement {#applicable?} to define eligibility-specific logic
        #
        # @example Basic usage
        #   result = SomeEligibilityReconciler.new.call({
        #     applicant: applicant,
        #     active_applicant_enrollments: active_applicant_enrollments,
        #     enrollment: enrollment
        #   })
        #
        # @see ReconcileAptcCsrEligibility
        # @see ReconcileIndividualMarketEligibility
        class BaseReconcileEligibility
          include Dry::Monads[:do, :result]

          # Performs eligibility reconciliation
          #
          # @param params [Hash] Parameters containing applicant, active_applicant_enrollments, and enrollment
          # @option params [FinancialAssistance::Applicant, IndividualMarket::Applicant] :applicant The applicant whose eligibility is being reconciled
          # @option params [Array<HbxEnrollment>] :active_applicant_enrollments Active enrollments where the applicant is a member
          # @option params [HbxEnrollment] :enrollment The specific enrollment that triggered reconciliation
          #
          # @return [Dry::Monads::Success, Dry::Monads::Failure] Success with reconciliation result or Failure with error
          def call(params)
            yield validate(params)
            reconciliation_result = yield perform_reconciliation(params)
            Success(reconciliation_result)
          end

          private

          # Validates input parameters
          #
          # @param params [Hash] Input parameters
          # @return [Dry::Monads::Success, Dry::Monads::Failure] Success with validated params or Failure with error
          def validate(params)
            @applicant = params[:applicant]
            @enrollment = params[:enrollment]
            @active_applicant_enrollments = params[:active_applicant_enrollments]
            return Failure('Missing applicant') unless @applicant.present?
            return Failure('Missing active_applicant_enrollments') unless @active_applicant_enrollments
            return Failure('Missing enrollment') unless @enrollment.present?

            Success(params)
          end

          # Performs the reconciliation logic
          #
          # @param _params [Hash] Validated parameters (unused in base implementation)
          # @return [Dry::Monads::Success, Dry::Monads::Failure] Success with result or Failure if no reconciliation needed
          def perform_reconciliation(_params)
            return Success({ reconciled: false, reason: 'No reconciliation needed' }) unless needs_reconciliation?

            reconcile
            Success({ reconciled: true, eligibility: eligibility })
          rescue StandardError => e
            Failure("Reconciliation failed: #{e.message}")
          end

          # Adjusts the eligibility by escalating or downgrading evidences based on applicability in regards to the enrollment
          #
          # This is the core adjustment process that either escalates or downgrades eligibility
          # evidence based on the eligibility's applicability in the context of the enrollment change.
          #
          # @return [void]
          def reconcile
            action = 'enrollment_purchase'
            message = "Enrollment #{@enrollment.hbx_id} has been purchased"

            applicable? ? eligibility.escalate_evidences_to_outstanding(action, message) : eligibility.downgrade_evidences_to_nrr(action, message)
          end

          # Determines if this eligibility should be reconciled.
          #
          # Base implementation checks if the eligibility exists.
          #
          # @return [Boolean] True if the eligibility needs reconciliation, false otherwise
          def needs_reconciliation?
            eligibility.present?
          end

          # Gets the eligibility from the applicant - must be implemented by subclasses
          #
          # @abstract Subclasses must implement this method
          # @return [Object] The eligibility object
          def eligibility
            raise NotImplementedError, "Subclasses must implement #eligibility"
          end

          # Determines if the eligibility is relevant, i.e., if it should be escalated or downgraded
          #
          # Abstract method that must be implemented by subclasses to define
          # eligibility-specific business logic for determining relevance.
          #
          # @abstract Subclasses must implement this method
          #
          # @return [Boolean] True if eligibility should be escalated, false if it should be downgraded
          def applicable?
            raise NotImplementedError, "Subclasses must implement #applicable?"
          end

          # Checks if an applicant is enrolled in any active enrollments
          #
          # @return [Boolean] True if the applicant is enrolled in any active enrollment
          def applicant_enrolled?
            @active_applicant_enrollments&.any? == true
          end
        end
      end
    end
  end
end
