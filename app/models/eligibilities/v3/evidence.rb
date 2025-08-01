# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    # Represents evidence used to verify an individual's eligibility for benefits
    #
    # Evidence is a fact, typically obtained from an external service, that contributes
    # to determining whether a subject is eligible to make use of a benefit resource.
    # This model supports the verification workflow process including document uploads,
    # state transitions, and integration with verification services.
    #
    # @example Creating a new evidence
    #   eligibility.evidences.build(_type: 'Eligibilities::Evidences::AliveEvidence')
    #
    class Evidence
      include Mongoid::Document
      include Mongoid::Timestamps
      include ::HasDocument
      include GlobalID::Identification

      embedded_in :eligibility, class_name: 'Eligibilities::V3::Eligibility'

      embeds_many :exhibits, class_name: 'Eligibilities::V3::Exhibit', cascade_callbacks: true

      # Accepted states
      STATUSES = %i[initial verification_succeeded verification_failed].freeze

      # key stores information about which type of evidence it is.
      # income_evidence, local_mec_evidence, esi_mec_evidence, non_esi_mec_evidence, citizenship_evidence, immigration_status_evidence
      field :key, type: String

      field :title, type: String
      field :description, type: String

      # The method determine_evidence will let us know if the evidence is satisfied or not.
      # We want to persist the result of this method in is_satisfied field for querying purposes.
      field :is_satisfied, type: Boolean, default: false

      field :determined_at, type: DateTime

      # Replacement for aasm_state. Tells the current state of the evidence.
      field :current_state, type: Symbol, default: :initial

      validates_presence_of :key, :is_satisfied

      # future implementation which will include workflow state transitions
      # and version details
      # embeds_one :chronicle, class_name: "Time::Chronicle"

      scope :by_key, ->(key) { where(key: key.to_sym) }

      # refers from the child class
      # this is a command that will determine the evidence is satisfied or not.
      # set the is_satified here and current_state
      def determine_evidence; end

      # State histories is moved to the Sub classes of Eligibility.
      # # TODO: Add newest as a scope on the Eligible::StateHistory and depend on it to get the latest.
      # def latest_state_history
      #   state_histories.last
      # end

      # Method is to retain current_state and due_on from the current evidence.
      # This is used in the context of the system generated applications like renewals and expired_rop.
      #
      # @param current_evidence [Eligibilities::V3::Evidence] The evidence from the current application
      #
      # @return [void]
      def retain_evidence_information(current_evidence)
        pre_state = self.current_state
        new_state = current_evidence.current_state

        self.current_state = new_state
        self.add_to_history(
          'retain_evidence_info_on_renewal',
          "Current state is retained from the previous application: #{pre_state} to #{new_state}",
          'system'
        )

        return unless current_evidence.due_on.present?

        self.due_on = current_evidence.due_on
        self.add_to_history(
          'retain_evidence_info_on_renewal',
          "Due date is retained from the previous application: #{current_evidence.due_on}",
          'system'
        )
      end
    end
  end
end
