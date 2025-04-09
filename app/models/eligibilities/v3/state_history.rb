# frozen_string_literal: true

module Eligibilities
  module V3
    # Tracks state transition history for objects that need to maintain a record of status changes.
    # This model stores information about state transitions including the previous state, new state,
    # transition timestamp, eligibility status, and additional metadata.
    #
    # Uses a polymorphic embedded relationship to allow multiple model types to track their state history
    # without requiring separate implementations for each model. This approach enables any model to
    # embed state histories by simply including the appropriate concern and setting up the relationship.
    #
    # @example Adding state history to a model
    #   class Application
    #     include Mongoid::Document
    #     embeds_many :state_histories, as: :status_trackable
    #
    #     def record_transition(from_state, to_state)
    #       state_histories.build(
    #         from_state: from_state,
    #         to_state: to_state,
    #         transition_at: Time.current,
    #         effective_on: Date.current
    #       )
    #     end
    #   end
    class StateHistory
      include Mongoid::Document
      include Mongoid::Timestamps

      # @!attribute status_trackable
      #   @return [Object] The polymorphic parent object that owns this state history
      embedded_in :status_trackable, polymorphic: true

      # @!attribute effective_on
      #   @return [Date] The date when the state change becomes effective
      field :effective_on, type: Date

      # @!attribute is_eligible
      #   @return [Boolean] Whether the state transition results in an eligible status
      field :is_eligible, type: Boolean, default: false

      # @!attribute metadata
      #   @return [Hash] Additional contextual information about the transition
      #   @note Used to store supplementary data that might be specific to certain transitions
      #         This is one additional field that is in WorkflowStateTransition but not in Eligible::StateHistory.
      field :metadata, type: Hash, default: {}

      # @!attribute from_state
      #   @return [Symbol] The previous state before transition
      field :from_state, type: Symbol

      # @!attribute to_state
      #   @return [Symbol] The new state after transition
      field :to_state, type: Symbol

      # @!attribute transition_at
      #   @return [DateTime] When the transition occurred
      field :transition_at, type: DateTime

      # @!attribute event
      #   @return [Symbol] The event that triggered this state transition
      field :event, type: Symbol

      # @!attribute comment
      #   @return [String] Optional comment describing reason for the transition
      field :comment, type: String

      # @!attribute reason
      #   @return [String] Specific reason code or description for the transition
      field :reason, type: String

      validates_presence_of :effective_on,
                            :is_eligible,
                            :from_state,
                            :to_state,
                            :transition_at

      # @!scope class
      # @return [Mongoid::Criteria] StateHistories with specified destination state
      scope :by_state,    ->(state) { where(to_state: state.to_sym) }

      # @!scope class
      # @return [Mongoid::Criteria] StateHistories that aren't transitions to initial state
      scope :non_initial, -> { where(:to_state.ne => :initial) }

      # @!scope class
      # @return [Mongoid::Criteria] StateHistories where is_eligible is true
      scope :eligible,    -> { where(:is_eligible => true) }

      # @!scope class
      # @return [Mongoid::Criteria] The most recent StateHistory based on creation timestamp
      # @note Uses limit(1) to optimize query performance by instructing MongoDB to stop
      #   after finding the first matching record, reducing database load and network transfer.
      #   Without this limit, MongoDB would retrieve and sort all records unnecessarily.
      scope :newest,      -> { order_by(created_at: :desc).limit(1) }
    end
  end
end
