# frozen_string_literal: true

module Eligibilities
  module V3
    # Evidence utility class for AptcCsr and IndividualMarket eligibility
    # Module is used to include the common methods, fields, validations, associations etc of all the evidences related to AptcCsr and IndividualMarket eligibility.
    module EvidenceUtils
      extend ActiveSupport::Concern

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
      #   STATE_TRANSITIONS[:attest][:from] # Returns array of states from which :attest is allowed
      #   STATE_TRANSITIONS[:attest][:to]   # Returns the destination state after :attest event
      STATE_TRANSITIONS = {
        attest: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :attested
        },
        move_to_rejected: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :rejected
        },
        negative_response_received: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :negative_response_received
        },
        move_to_unverified: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :unverified
        },
        move_to_outstanding: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :outstanding
        },
        move_to_verified: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :verified
        },
        move_to_review: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :review
        },
        move_to_pending: {
          from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified],
          to: :pending
        }
        # TODO: Some of the states defined below are not defined in the STATES constant.
        #       We need to review the states, add them to the STATES constant if they are valid,
        #       and then uncomment the below code.
        # determined: {
        #   from: [:requested, :review_required, :corrected],
        #   to: :determined
        # },
        # expired: {
        #   from: [:requested],
        #   to: :expired
        # },
        # denied: {
        #   from: [:requested],
        #   to: :denied
        # },
        # errored: {
        #   from: [:requested, :errored, :corrected],
        #   to: :errored
        # },
        # corrected: {
        #   from: [:errored],
        #   to: :corrected
        # },
        # closed: {
        #   from: [:pending, :requested, :review_required, :expired, :denied, :errored, :closed],
        #   to: :closed
        # }
      }.freeze

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

        # Define state predicate methods for all states
        # @example
        #   evidence.attested? # Returns true if current_state is :attested
        #
        # @return [Boolean] true if the current state matches the method name state
        STATES.each do |state|
          define_method("#{state}?") do
            current_state == state
          end
        end

        # Define event methods for all state transitions
        STATE_TRANSITIONS.each_key do |event|

          # Define a method to check if the event can be triggered from the current state
          # @example
          #   evidence.may_attest? # Returns true if the current state allows the :attest event
          # @return [Boolean] true if the event can be triggered from the current state
          define_method("may_#{event}?") do
            STATE_TRANSITIONS[event][:from].include?(current_state)
          end

          # Define a method to trigger the event and transition to the new state
          # @example
          #   evidence.attest(comment: 'Verified by doctor', reason: 'Alive') # Transitions to :attested state
          # @param comment [String] Optional comment for the state transition
          # @param reason [String] Optional reason for the state transition
          # @raise [ArgumentError] if the event cannot be triggered from the current state
          # @return [void]
          define_method(event) do |comment = nil, reason = nil|
            transition_state(event, comment, reason)
          end
        end

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

        private

        # Handles state transitions with validation and state history tracking
        # @param event [Symbol] The event triggering the state transition
        # @param comment [String, nil] Optional comment about why the state changed
        # @param reason [String, nil] Optional reason code for the state change
        # @raise [ArgumentError] When current_state is invalid or transition is not allowed
        # @return [void]
        def transition_state(event, comment = nil, reason = nil)
          raise(ArgumentError, "Invalid from_state: #{current_state}") if STATES.exclude?(current_state)

          transition = STATE_TRANSITIONS[event]
          raise(ArgumentError, "Cannot #{event} from state: #{current_state}") unless send("may_#{event}?")

          from_state = current_state
          self.current_state = transition[:to]
          state_histories.build(
            effective_on: Date.today,
            from_state: from_state,
            to_state: transition[:to],
            transition_at: DateTime.now,
            event: event,
            comment: comment,
            reason: reason
          )
        end
      end
    end
  end
end
