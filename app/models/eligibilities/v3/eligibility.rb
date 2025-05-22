# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    # Base class for various types of eligibility determinations
    #
    # @abstract Various eligibility types extend this base class
    # @example Types of eligibility
    #   - individual_market_eligibility
    #   - magi_medicaid_eligibility
    #   - aptc_csr_eligibility
    #   - osse_shop_eligibility
    #
    # @example Application types and their eligibilities
    #   An individual market application will have:
    #   - individual_market_eligibility
    #   - aptc_csr_eligibility
    #
    #   A financial assistance application will have:
    #   - individual_market_eligibility
    #   - magi_medicaid_eligibility
    #   - aptc_csr_eligibility
    class Eligibility
      include Mongoid::Document
      include Mongoid::Timestamps
      include StateMachine

      # @!attribute eligible
      #   @return [Object] The entity (polymorphic) to which this eligibility belongs
      embedded_in :eligible, polymorphic: true

      # Collection of determinations associated with this eligibility
      #
      # @note Uses Single Table Inheritance (STI) pattern to store different types
      #   of determinations in the same collection
      # @example Types of determinations
      #   - qhp_determination
      #   - csr_determination
      #   - aptc_determination
      #   - magi_medicaid_determination
      # @!attribute determinations
      #   @return [Array<Eligibilities::V3::Determination>] List of determinations
      embeds_many :determinations, class_name: 'Eligibilities::V3::Determination', cascade_callbacks: true

      # Collection of evidence supporting this eligibility
      #
      # @note Uses Single Table Inheritance (STI) pattern to store different types
      #   of evidence in the same collection
      # @example Types of evidence
      #   - social_security_number
      #   - american_indian_status
      #   - citizenship
      #   - immigration_status
      #   - alive_status
      #   - income
      #   - esi_mec
      #   - non_esi_mec
      #   - local_mec
      # @!attribute evidences
      #   @return [Array<Eligibilities::V3::Evidence>] List of evidence documents
      embeds_many :evidences, class_name: 'Eligibilities::V3::Evidence', cascade_callbacks: true

      # future implementation which will include workflow state transitions
      # and version details
      # embeds_one :chronicle, class_name: "Time::Chronicle"

      # TODO: This needs to be implemented when we start using grants.
      # embeds_many :grants, class_name: "::Eligibilities::V3::Grant", as: :grantable

      EVIDENCES = [].freeze # Should be listing the evidences in the child classes.

      # key stores information about which type of eligibility it is.
      # individual_market_eligibility, magi_medicaid_eligibility, aptc_csr_eligibility, osse_shop_eligibility
      field :key, type: Symbol
      field :title, type: String
      field :description, type: String

      # Replacement for aasm_state. Tells the current state of the eligibility.
      field :current_state, type: Symbol, default: :initial

      # To check if the eligibility is satisfied depending on the evidences' satisfaction.
      field :is_satisfied, type: Boolean, default: false
      field :determined_at, type: DateTime
      field :is_disqualified, type: Boolean, default: false
      field :disqualified_at, type: DateTime
      field :disqualified_reason, type: String

      validates_presence_of :title
      validates_uniqueness_of :key

      scope :by_key, ->(key) { where(key: key.to_sym) }
      scope :eligible, -> { where(current_state: :eligible) }
      scope :ineligible, -> { where(current_state: :ineligible) }
      scope :disqualified, -> { where(is_disqualified: true) }

      # Defines the possible states for an eligibility object.
      # These states represent the lifecycle of an eligibility determination and its associated evidences.
      #
      # @note The `current_state` field in the `Eligibility` model uses these states to track the eligibility's status.
      #
      # @example States and their meanings:
      #   - `:initial`: The default state when the eligibility is created.
      #
      #   - `:unsatisfied`: Indicates that all members are determined ineligible for the eligibility, or all evidences are not satisfied.
      #     - Example 1: All applicants applying for coverage are ineligible for APTC and CSR in `APTC_CSR_eligibility`.
      #     - Example 2: All applicants applying for coverage are ineligible for QHP in `IndividualMarketEligibility`.
      #     - Example 3: Evidences are in an outstanding state, and the ROP (Reasonable Opportunity Period) has expired.
      #
      #   - `:preliminary_eligible`: Indicates that application is determined and the eligibility evidences are eligible for determination
      #
      #   - `:verification_in_progress`: Indicates that evidences are in the process of being verified.
      #
      #   - `:satisfied`: Indicates that all evidences are eligible in one of these states `verified` or `attested`.
      #
      # @return [Array<Symbol>] List of possible states for an eligibility object.
      STATES = [
        :initial,
        :unsatisfied,
        :preliminary_eligible,
        :verification_in_progress,
        :satisfied
      ].freeze

      # Defines the possible events that can trigger state transitions for an eligibility object.
      #   refer to the Eligibilities::V3::StateMachine module for more details.
      state_transitions do
        action :move_to_initial, from: [nil], to: :initial
        action :pend, from: [:initial, :unsatisfied, :preliminary_eligible, :satisfied], to: :verification_in_progress
        action :satisfy, from: [:initial, :unsatisfied, :preliminary_eligible, :verification_in_progress], to: :satisfied
        action :unsatisfy, from: [:initial, :preliminary_eligible, :verification_in_progress, :satisfied], to: :unsatisfied
        action :prequalify, from: [:initial], to: :preliminary_eligible
      end

      # This method can be implemented in Domain Model as well.
      def determine_eligibility
        # evidences.each do |evidence|
        #   evidence.determine_evidence_state
        # end

        # Loop through all the evidences and check if they are satisfied.
        # Also, update is_satisfied field to be able to query if the eligibility is satisfied.
        # This is a performance enhancement to avoid querying all the evidences to check if the eligibility is satisfied.
        # and set the current_state to eligible or ineligible based on the evidences' satisfaction.
        # and set the determined_at.
      end
    end
  end
end
