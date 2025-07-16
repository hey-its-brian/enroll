# frozen_string_literal: true

module Eligibilities
  module V3
    # Eligibility determination for Advanced Premium Tax Credit (APTC) and Cost Sharing Reduction (CSR)
    #
    # This class handles the eligibility process for consumers seeking
    # financial assistance through APTC and CSR subsidies. It includes tracking
    # eligibility state history and validating evidence requirements.
    #
    # @example Creating an APTC/CSR eligibility
    #   applicant.eligibilities.build(
    #     _type: 'Eligibilities::V3::AptcCsrEligibility',
    #     title: 'APTC/CSR Eligibility',
    #     key: :aptc_csr_eligibility,
    #   )
    class AptcCsrEligibility < ::Eligibilities::V3::Eligibility
      include ::Eligibilities::V3::EligibilityUtils
      # A replacement model for WorkflowStateTransition.
      # In future, we will use has_chronicle that could potentially include both versions of the current model and its state history.
      # This is the reason why the state_histories association is added here and not in the parent class.
      #
      # @!attribute state_histories
      #   @return [Array<StateHistory>] The history of state transitions for this eligibility
      embeds_many :state_histories, class_name: 'Eligibilities::V3::StateHistory', as: :status_trackable, cascade_callbacks: true

      # A defined list of evidence types for this eligibility
      EVIDENCES = ['esi_mec_evidence', 'income_evidence', 'local_mec_evidence', 'non_esi_mec_evidence'].freeze

      validate :unique_evidences

      # Returns the most recent state history record
      #
      # This method retrieves the newest state history record for this eligibility.
      # The result is memoized to avoid repeated database queries.
      #
      # @return [StateHistory, nil] The most recent state history record, or nil if none exists
      def latest_state_history
        return @latest_state_history if defined?(@latest_state_history)

        @latest_state_history = state_histories.newest.first
      end

      # Retrieves an evidence instance based on the evidence type string
      #
      # @param evidence_type [String] The type of evidence to retrieve
      # @return [FinancialAssistance::Evidences::BaseEvidence, nil] The requested evidence or nil if not found
      def fetch_evidence(evidence_type)
        {
          'income_evidence' => income_evidence,
          'esi_evidence' => esi_mec_evidence,
          'non_esi_evidence' => non_esi_mec_evidence,
          'local_mec_evidence' => local_mec_evidence
        }[evidence_type]
      end

      # Retrieves the ESI MEC evidence record for this eligibility
      #
      # @return [FinancialAssistance::Evidences::EsiMecEvidence, nil] The ESI MEC evidence or nil if not found
      def esi_mec_evidence
        evidences.where(_type: 'FinancialAssistance::Evidences::EsiMecEvidence').first
      end

      # Retrieves the income evidence record for this eligibility
      #
      # @return [FinancialAssistance::Evidences::IncomeEvidence, nil] The income evidence or nil if not found
      def income_evidence
        evidences.where(_type: 'FinancialAssistance::Evidences::IncomeEvidence').first
      end

      # Retrieves the local MEC evidence record for this eligibility
      #
      # @return [FinancialAssistance::Evidences::LocalMecEvidence, nil] The local MEC evidence or nil if not found
      def local_mec_evidence
        evidences.where(_type: 'FinancialAssistance::Evidences::LocalMecEvidence').first
      end

      # Retrieves the non-ESI MEC evidence record for this eligibility
      #
      # @return [FinancialAssistance::Evidences::NonEsiMecEvidence, nil] The non-ESI MEC evidence or nil if not found
      def non_esi_mec_evidence
        evidences.where(_type: 'FinancialAssistance::Evidences::NonEsiMecEvidence').first
      end

      def determine_eligibility_state(reason)
        return unless evidences.present?

        if evidences.all? { |evidence| %i[verified attested].include?(evidence.current_state.to_sym) }
          assign_attributes(is_satisfied: true, determined_at: TimeKeeper.date_of_record)
          satisfy(reason: reason) if can_satisfy?
        elsif can_pend?
          assign_attributes(is_satisfied: false, determined_at: TimeKeeper.date_of_record)
          pend(reason: reason)
        end
      end

      # Extends the due date for income evidence if it exists
      #
      # @param action [String] The action that triggered the due date extension
      # @param extend_by [Integer] Number of days to extend the due date by
      # @param modified_by [String] Identifier of the user or process that modified the due
      #
      # @return [void]
      def extend_income_evidence_due_dates(action, extend_by, modified_by)
        income_evidence.extend_due_date(action, extend_by, modified_by) if income_evidence.present?
      end

      private

      # Adds to errors collection if duplicate evidence types are found
      # @return [void]
      def unique_evidences
        evidence_types = evidences.pluck(:_type)
        errors.add(:evidences, 'cannot have duplicate evidence types') if evidence_types.uniq.length != evidence_types.length
      end
    end
  end
end
