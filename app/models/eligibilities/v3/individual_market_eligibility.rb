# frozen_string_literal: true

module Eligibilities
  module V3
    # Eligibility determination for Individual Market enrollment
    #
    # This class handles the eligibility process for consumers seeking
    # to enroll in Individual Market health plans. It includes tracking
    # eligibility state history and validating evidence requirements.
    #
    # @example Creating an individual market eligibility
    #   applicant.eligibilities.build(
    #     _type: 'Eligibilities::V3::IndividualMarketEligibility',
    #     title: 'Individual Market Eligibility',
    #     key: :individual_market_eligibility,
    #   )
    class IndividualMarketEligibility < ::Eligibilities::V3::Eligibility

      # A replacement model for WorkflowStateTransition.
      # In future, we will use has_chronicle that could potentially include both versions of the current model and its state history.
      # This is the reason why the state_histories association is added here and not in the parent class.
      #
      # @!attribute state_histories
      #   @return [Array<StateHistory>] The history of state transitions for this eligibility
      embeds_many :state_histories, class_name: 'Eligibilities::V3::StateHistory', as: :status_trackable, cascade_callbacks: true

      # A defined list of evidence types for this eligibility
      EVIDENCES = ['alive_evidence', 'american_indian_evidence', 'citizenship_evidence', 'immigration_evidence', 'social_security_number_evidence'].freeze

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
