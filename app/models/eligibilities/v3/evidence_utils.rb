# frozen_string_literal: true

module Eligibilities
  module V3
    # Evidence utility class for AptcCsr and IndividualMarket eligibility
    # Module is used to include the common methods, fields, validations, associations etc of all the evidences related to AptcCsr and IndividualMarket eligibility.
    module EvidenceUtils
      extend ActiveSupport::Concern
      include StateMachine

      # All possible states for evidence verification
      # @return [Array<Symbol>] List of all possible states for the state machine
      STATES = [
        :initial,
        :attested,
        :pending,
        :review,
        :outstanding,
        :verified,
        :unverified,
        :negative_response_received,
        :determined,
        :expired,
        :denied,
        :errored,
        :closed,
        :corrected,
        :rejected
      ].freeze

      # Definition of all allowed state transitions
      # @return [Hash] Map of event names to transition rules
      # @example
      #   STATE_TRANSITIONS[:move_to_attested][:from] # Returns array of states from which :move_to_attested is allowed
      #   STATE_TRANSITIONS[:move_to_attested][:to]   # Returns the destination state after :move_to_attested event
      state_transitions do
        action :move_to_attested, from: [:initial, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified], to: :attested
        action :move_to_rejected, from: [:attested, :negative_response_received, :outstanding, :pending, :review, :unverified, :verified], to: :rejected
        action :negative_response_received, from: [:attested, :outstanding, :pending, :rejected, :review, :unverified, :verified], to: :negative_response_received
        action :move_to_unverified, from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :verified], to: :unverified
        action :move_to_outstanding, from: [:attested, :negative_response_received, :pending, :rejected, :review, :unverified, :verified], to: :outstanding
        action :move_to_verified, from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified], to: :verified
        action :move_to_review, from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :unverified, :verified], to: :review
        action :move_to_pending, from: [:attested, :initial, :negative_response_received, :outstanding, :rejected, :review, :unverified, :verified], to: :pending
      end

      included do
        # In future, we will use has_chronicle that could potentially include both versions of the current model and its state history.
        # This is the reason why the below associations are added here and not in 'Eligibilities::V3::Evidence' class.
        embeds_many :state_histories, class_name: 'Eligibilities::V3::StateHistory', as: :status_trackable, cascade_callbacks: true
        embeds_many :verification_histories, class_name: 'Eligibilities::V3::VerificationHistory', cascade_callbacks: true
        embeds_many :request_results, class_name: 'Eligibilities::V3::RequestResult', cascade_callbacks: true

        field :verification_outstanding, type: Mongoid::Boolean, default: false
        field :due_on, type: Date
        field :external_service, type: String
        field :updated_by, type: String
        field :due_on_type, type: String # admin, notice

        # @!attribute [rw] is_active
        #   @return [Boolean] Indicates whether the evidence is currently active.
        #   @note This field is primarily used to track the active status of verification types.
        #   @deprecated This field is deprecated and will not be used in future implementations.
        #   @details
        #     - This field allows toggling between active and inactive states for certain verification types, such as citizenship or immigration status.
        #     - Both active and inactive statuses are stored for a person, along with historical verification information.
        #     - It will be used for migration of all verification types to an application but is no longer relevant for subsequent applications.
        field :is_active, type: Mongoid::Boolean, default: true

        # Validates that current_state is one of the defined states
        # @note Allows nil values
        validates :current_state, inclusion: { in: STATES }, allow_nil: false

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

        # Returns the most recent verification history record
        #
        # This method retrieves the newest verification history record for this eligibility.
        # The result is memoized to avoid repeated database queries.
        #
        # @return [VerificationHistory, nil] The most recent verification history record, or nil if none exists
        def latest_verification_history
          return @latest_verification_history if defined?(@latest_verification_history)

          @latest_verification_history = verification_histories.newest.first
        end

        def set_verified
          self.move_to_verified if can_move_to_verified?
        end

        # Needs to be updated once we have the requirements for the rejected state
        def set_failed
          if self.reload.current_state == :rejected
            move_to_rejected
          else
            person = eligibility&.eligible&.find_person
            return negative_response_received unless person

            is_enrolled = person.families&.any? { |family| family.person_has_an_active_enrollment?(person) }
            (is_enrolled ? move_to_outstanding : negative_response_received)
          end
          return unless EnrollRegistry.feature_enabled?(:set_due_date_upon_response_from_hub)

          evidence_document_due = EnrollRegistry[:verification_document_due_in_days].item
          self.due_on = TimeKeeper.date_of_record + evidence_document_due.days
          self.due_on_type = 'response_from_hub'

          true
        end
      end
    end
  end
end
