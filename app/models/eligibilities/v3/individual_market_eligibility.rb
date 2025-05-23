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

      # Retrieves an evidence instance based on the evidence type string
      #
      # @param evidence_type [String] The type of evidence to retrieve
      # @return [FinancialAssistance::Evidences::BaseEvidence, nil] The requested evidence or nil if not found
      def fetch_evidence(evidence_type)
        {
          'immigration_status' => immigration_evidence,
          'citizenship' => citizenship_evidence,
          'american_indian_status' => american_indian_evidence,
          'social_security_number' => social_security_number_evidence,
          'residency' => residency_evidence,
          'alive_status' => alive_evidence
        }[evidence_type]
      end

      # Retrieves the immigration evidence record for this eligibility
      #
      # @return [Eligibilities::V3::Evidences::ImmigrationEvidence, nil] The immigration evidence or nil if not found
      def immigration_evidence
        evidences.where(_type: 'Eligibilities::V3::Evidences::ImmigrationEvidence').first
      end

      # Retrieves the citizenship evidence record for this eligibility
      #
      # @return [Eligibilities::V3::Evidences::CitizenshipEvidence, nil] The citizenship evidence or nil if not found
      def citizenship_evidence
        evidences.where(_type: 'Eligibilities::V3::Evidences::CitizenshipEvidence').first
      end

      # Retrieves the American Indian evidence record for this eligibility
      #
      # @return [Eligibilities::V3::Evidences::AmericanIndianEvidence, nil] The American Indian evidence or nil if not found
      def american_indian_evidence
        evidences.where(_type: 'Eligibilities::V3::Evidences::AmericanIndianEvidence').first
      end

      # Retrieves the social security number evidence record for this eligibility
      #
      # @return [Eligibilities::V3::Evidences::SocialSecurityNumberEvidence, nil] The social security number evidence or nil if not found
      def social_security_number_evidence
        evidences.where(_type: 'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence').first
      end

      # Retrieves the residency evidence record for this eligibility
      #
      # @return [Eligibilities::V3::Evidences::ResidencyEvidence, nil] The residency evidence or nil if not found
      def residency_evidence
        evidences.where(_type: 'Eligibilities::V3::Evidences::ResidencyEvidence').first
      end

      # Retrieves the alive evidence record for this eligibility
      #
      # @return [Eligibilities::V3::Evidences::AliveEvidence, nil] The alive evidence or nil if not found
      def alive_evidence
        evidences.where(_type: 'Eligibilities::V3::Evidences::AliveEvidence').first
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
