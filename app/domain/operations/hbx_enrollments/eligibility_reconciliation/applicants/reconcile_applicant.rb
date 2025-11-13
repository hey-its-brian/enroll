# frozen_string_literal: true

module Operations
  module HbxEnrollments
    module EligibilityReconciliation
      module Applicants
        # Orchestrates eligibility reconciliation for a single applicant
        #
        # Coordinates APTC/CSR and Individual Market eligibility reconciliation by
        # delegating to specialized reconciler classes. For each eligibility type,
        # determines if reconciliation is needed and adjusts eligibilities by requiring
        # or waiving based on enrollment changes to maintain evidence consistency.
        #
        # Reconciliation is the process of marrying enrollment status with eligibility
        # evidences through adjustment based on enrollment-specific applicability rules.
        #
        # @param params [Hash] Parameters containing applicant, enrollment, and active enrollments
        # @option params [FinancialAssistance::Applicant] :applicant The applicant to reconcile
        # @option params [HbxEnrollment] :enrollment The enrollment that triggered reconciliation
        # @option params [Array<HbxEnrollment>] :active_enrollments Pre-fetched active enrollments for performance
        #
        # @return [Dry::Monads::Success, Dry::Monads::Failure] Success with reconciliation results or Failure with error
        #
        # @see Eligibilities::ReconcileAptcCsrEligibility
        # @see Eligibilities::ReconcileIndividualMarketEligibility
        class ReconcileApplicant
          include Dry::Monads[:do, :result]

          ELIGIBILITY_KEYS = ::Eligibilities::V3::EligibilityUtils::ELIGIBILITY_CLASSES.keys.freeze

          # Performs eligibility reconciliation for the applicant
          #
          # @param params [Hash] Parameters containing applicant, enrollment, and active enrollments
          # @option params [FinancialAssistance::Applicant] :applicant The applicant whose eligibilities will be reconciled
          # @option params [HbxEnrollment] :enrollment The enrollment that triggered the reconciliation
          # @option params [Array<HbxEnrollment>] :active_enrollments Pre-fetched active enrollments for performance
          #
          # @return [Dry::Monads::Success, Dry::Monads::Failure] Success with reconciliation results or Failure with error
          def call(params)
            yield validate(params)
            active_applicant_enrollments = filter_active_applicant_enrollments
            results = yield reconcile_eligibilities(active_applicant_enrollments)
            Success(results)
          end

          private

          # Validates input parameters
          #
          # @param params [Hash] Input parameters containing applicant, enrollment, and active enrollments
          # @option params [FinancialAssistance::Applicant] :applicant The applicant to reconcile
          # @option params [HbxEnrollment] :enrollment The enrollment that triggered reconciliation
          # @option params [Array<HbxEnrollment>] :active_enrollments Active enrollments for performance
          #
          # @return [Dry::Monads::Success, Dry::Monads::Failure] Success with validated params or Failure with error
          def validate(params)
            @applicant = params[:applicant]
            @enrollment = params[:enrollment]
            @active_enrollments = params[:active_enrollments]
            return Failure('Missing applicant') unless @applicant.present?
            return Failure('Invalid applicant object') unless @applicant.is_a?(::FinancialAssistance::Applicant) || @applicant.is_a?(::IndividualMarket::Applicant)
            return Failure('Missing enrollment') unless @enrollment.present?
            return Failure('Invalid enrollment object') unless @enrollment.is_a?(::HbxEnrollment)
            return Failure('Missing active_enrollments') unless @active_enrollments.present?

            Success(@applicant)
          end

          # Selects active enrollments where the applicant is a member
          # @return [Array<HbxEnrollment>] Active enrollments where the applicant is a member
          def filter_active_applicant_enrollments
            @active_enrollments.select do |active_enrollment|
              active_enrollment.hbx_enrollment_members.where(applicant_id: @applicant.family_member_id).exists?
            end
          end

          # Reconciles all eligibility types for the applicant
          #
          # @param active_applicant_enrollments [Array<HbxEnrollment>] Active enrollments where the applicant is a member
          # @return [Dry::Monads::Success, Dry::Monads::Failure] Success with results or Failure with error
          def reconcile_eligibilities(active_applicant_enrollments)
            results = ELIGIBILITY_KEYS.reduce({}) do |reconciler_accumulator, type|
              reconciliation_result = reconcile_eligibility_type(type, active_applicant_enrollments)
              return reconciliation_result if reconciliation_result.failure?
              reconciler_accumulator[type] = reconciliation_result.value!
              reconciler_accumulator
            end

            Success(results)
          rescue StandardError => e
            Failure("Failed to reconcile eligibilities: #{e.message}")
          end

          # Reconciles a specific eligibility type using the appropriate reconciler
          #
          # Creates the appropriate reconciler instance based on the eligibility type
          # and delegates the reconciliation logic to that specialized class.
          #
          # @param type [Symbol] The eligibility type
          # @param active_applicant_enrollments [Array<HbxEnrollment>] Active enrollments where the applicant is a member
          # @return [Dry::Monads::Success, Dry::Monads::Failure] Success or Failure with reconciliation result
          # @raise [ArgumentError] If an unknown eligibility type is provided
          def reconcile_eligibility_type(type, active_applicant_enrollments)
            raise ArgumentError, "Unknown eligibility type: #{type}" unless ELIGIBILITY_KEYS.include?(type)

            reconciler_class = reconciler_class_for(type)
            reconciler_class.new.call(applicant: @applicant, enrollment: @enrollment, active_applicant_enrollments: active_applicant_enrollments)
          end

          # Returns the appropriate reconciler class for the eligibility type
          #
          # @param type [Symbol] The eligibility type
          # @return [Class] The reconciler class
          # @raise [ArgumentError] If no reconciler class is found for the eligibility type
          def reconciler_class_for(type)
            case type
            when :individual_market_eligibility
              Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileIndividualMarketEligibility
            when :aptc_csr_eligibility
              Operations::HbxEnrollments::EligibilityReconciliation::Eligibilities::ReconcileAptcCsrEligibility
            else
              raise ArgumentError, "No reconciler class found for eligibility type: #{type}"
            end
          end
        end
      end
    end
  end
end
