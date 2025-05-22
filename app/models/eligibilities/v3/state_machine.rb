# frozen_string_literal: true

module Eligibilities
  module V3
# The `StateMachine` module provides functionality for managing
# state transitions in a Ruby class. It allows developers to define states, actions,
# and guards dynamically, enabling flexible and reusable state management.
#
# ## Features
# - Dynamically defines state predicates (e.g., `initial?`) for each state.
# - Allows defining state transition actions (e.g., `verify`, `verify!`) with optional persistence.
# - Automatically generates guard methods (e.g., `can_verify?`) to check if a transition is allowed.
# - Supports custom logic during transitions via blocks.
#
# ## Usage
#
# To use the `StateMachine` module, include it in your class and define the `STATES` constant
# and the `state_transitions` block to specify the states and transitions.
#
# ### Example
#
# ```ruby
# class Eligibility
#   include Eligibilities::V3::StateMachine
#
#   STATES = [:initial, :verified, :rejected].freeze
#
#   attr_accessor :current_state, :state_histories
#
#   def initialize
#     @current_state = :initial
#     @state_histories = []
#   end
#
#   state_transitions do
#     action :verify, from: [:initial], to: :verified
#     action :reject, from: [:verified], to: :rejected
#   end
# end
#
# eligibility = Eligibility.new
# eligibility.verify # Transition to `:verified`
# eligibility.can_reject? # => true
# eligibility.reject! # Transition to `:rejected` with persistence
# ```
#
# ### Notes
# - The `STATES` constant must be defined in the including class and should be an array of symbols.
# - The `current_state` attribute must be defined in the including class to track the current state.
# - The `state_histories` attribute is expected to be an array or ActiveRecord association for tracking state changes.
#
# ### Error Handling
# - Raises `RuntimeError` if the `STATES` constant is not defined.
# - Raises `RuntimeError` if an invalid state transition is attempted.
#
# ### Customization
# - You can pass a block to an action to execute custom logic during the transition.
# - The `persist` flag in the bang (`!`) methods ensures that transitions are persisted to the database.
#
    module StateMachine
      # Extends the including class with the ClassMethods module.
      #
      # @param host_class [Class] The class including the StateMachine module.
      def self.included(host_class)
        host_class.extend ClassMethods
      end

      # ClassMethods provides class-level methods for defining state transitions
      # and dynamically generating helper methods for states and actions.
      module ClassMethods
        # Defines allowable keys for state transition metadata
        #
        # @constant [Array<Symbol>]
        # @return [Array<Symbol>] List of allowed keys for state transition options
        # @note The :metadata key was intentionally excluded as it was not used in the
        #   current implementation, but it can be added if needed in the future.
        ALLOWED_KEYS = [:reason, :comment, :transition_at, :effective_on].freeze

        # Defines state transitions and dynamically generates predicate methods for states.
        #
        # @example
        #   state_transitions do
        #     action :verify, from: [:initial], to: :verified
        #     action :reject, from: [:verified], to: :rejected
        #   end
        #
        # @param block [Proc] The block defining the transitions.
        # @return [void]
        def state_transitions(&block)
          define_state_predicates
          # an example this method will be defined
          # @example
          #  def satisfy(**options)
          #    sanitized_options = options.to_h.slice(*ALLOWED_KEYS)
          #
          #    state_histories.build(
          #    from_state: current_state,
          #    to_state: :satisfied,
          #    event: :satisfy,
          #    transition_at: DateTime.now,
          #    effective_on: DateTime.now,
          #    reason: nil,
          #    comment: nil,
          #    metadata: nil
          #    )
          #    self.current_state = :satisfied
          #  end
          instance_eval(&block)
        end

        # Defines a state transition action and its associated guard method.
        #
        # @param action_name [Symbol] The name of the action (e.g., :verify).
        # @param from [Array<Symbol>] The valid states from which the transition can occur.
        # @param to [Symbol] The state to transition to.
        # @param block [Proc] Optional block to execute during the transition.
        # @return [void]
        def action(action_name, from:, to:, &block)
          define_action_method(action_name, from, to, &block)
          define_action_guard_method(action_name, from)
        end

        private

        # Dynamically defines predicate methods for each state in the `STATES` constant.
        # For example, if a state is `:initial`, it defines a method `initial?`.
        #
        # @raise [RuntimeError] If the `STATES` constant is not defined in the including class.
        # @return [void]
        def define_state_predicates
          raise "STATES constant must be defined in the including class" unless const_defined?(:STATES)

          self::STATES.each do |state|
            # an example this method will be defined
            # def initial?
            #   current_state == :initial
            # end
            # This method checks if the current state matches the state name
            define_method("#{state}?") do
              current_state == state
            end
          end
        end

        # Defines the method for triggering a state transition action.
        #
        # @param action_name [Symbol] The name of the action (e.g., :verify).
        # @param from [Array<Symbol>] The valid states from which the transition can occur.
        # @param to [Symbol] The state to transition to.
        # @param block [Proc] Optional block to execute during the transition.
        # @return [void]
        def define_action_method(action_name, from, to, &block)
          # Define a private method to handle the transition logic
          define_method("#{action_name}_transition") do |persist: false, **options|
            # Validate the current state and target state
            raise "Invalid transition from #{current_state} to #{to} for action #{action_name}" unless from.include?(current_state)
            raise "Invalid target state '#{to}' for action #{action_name}" unless self.class::STATES.include?(to)

            # Sanitize options to include only allowed keys
            sanitized_options = options.to_h.slice(*ALLOWED_KEYS)

            # Perform the state transition
            state_histories.build(
              from_state: current_state,
              to_state: to,
              event: persist ? "#{action_name}!" : action_name,
              transition_at: sanitized_options[:transition_at] || DateTime.now,
              effective_on: sanitized_options[:effective_on] || DateTime.now,
              reason: sanitized_options[:reason],
              comment: sanitized_options[:comment]
              # metadata: sanitized_options[:metadata] # Currently not used, enable if needed
            )
            self.current_state = to
            # Execute the block if provided
            instance_exec({}, &block) if block_given?

            save! if persist
          end

          # Define the regular action method
          define_method(action_name) do |**options|
            send("#{action_name}_transition", **options, persist: false)
          end

          # Define the bang (!) action method
          define_method("#{action_name}!") do |**options|
            raise "Base class object is not persisted" unless persisted?
            send("#{action_name}_transition", **options, persist: true)
          end

          private "#{action_name}_transition"
        end

        # Defines a guard method to check if the action can be triggered.
        # For example, for an action `:verify`, it defines a method `can_verify?`.
        #
        # @param action_name [Symbol] The name of the action (e.g., :verify).
        # @param from [Array<Symbol>] The valid states from which the transition can occur.
        # @return [void]
        def define_action_guard_method(action_name, from)
          define_method("can_#{action_name}?") do
            from.include?(current_state)
          end
        end
      end
    end
  end
end