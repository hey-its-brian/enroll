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
        action :move_to_negative_response_received, from: [:attested, :outstanding, :pending, :rejected, :review, :unverified, :verified], to: :negative_response_received
        action :move_to_outstanding, from: [:attested, :negative_response_received, :pending, :rejected, :review, :unverified, :verified], to: :outstanding
        action :move_to_verified, from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified], to: :verified
        action :move_to_review, from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :unverified, :verified], to: :review
        action :move_to_pending, from: [:attested, :initial, :negative_response_received, :outstanding, :rejected, :review, :unverified, :verified], to: :pending
        action :move_to_unverified, from: [:initial, :attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :verified], to: :unverified
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

        # @!attribute [rw] due_date_extended_at
        #   @return [DateTime] The date and time when the auto due date was extended.
        #                      This field is a read-only field that is set when the due date is automatically extended.
        #
        # @note An ROP can span across multiple applications, so, this timestamp can be older than the evidence/application created_at timestamp.
        #       This field needs to be only used in auto due date extension scenarios and not for manual/admin due date extensions.
        field :due_date_extended_at, type: DateTime

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

        # Creates a verification history on the evidence
        #
        # @option params [String] :action The action performed on the evidence
        # @option params [String] :update_reason The reason for the update
        # @option params [String] :updated_by The user or system that performed the update
        #
        # @return [VerificationHistory] The verification history record created
        def add_verification_history(action, update_reason, updated_by)
          verification_histories.build(action: action, update_reason: update_reason, updated_by: updated_by)
        end

        def schedule_verification_due_on
          verification_document_due = EnrollRegistry[:verification_document_due_in_days].item
          TimeKeeper.date_of_record + verification_document_due.days
        end

        def mark_as_outstanding
          return unless self.can_move_to_outstanding?

          self.move_to_outstanding
          assign_attributes(verification_outstanding: true, is_satisfied: false)
          self.due_on = schedule_verification_due_on if self.due_on.blank?
        end

        def mark_as_negative_response_received
          return unless self.can_move_to_negative_response_received?

          assign_attributes(verification_outstanding: false, is_satisfied: true, due_on: nil)
          self.move_to_negative_response_received
        end

        def mark_as_verified
          return unless self.can_move_to_verified?

          assign_attributes(verification_outstanding: false, is_satisfied: true, due_on: nil)
          self.move_to_verified
        end

        def mark_as_attested
          return unless self.can_move_to_attested?

          assign_attributes(verification_outstanding: false, is_satisfied: true, due_on: nil)
          self.move_to_attested
        end

        def mark_as_rejected
          return unless self.can_move_to_rejected?

          assign_attributes(verification_outstanding: true, is_satisfied: false)
          self.due_on = schedule_verification_due_on unless self.current_state == 'review'
          self.move_to_rejected
        end

        def mark_as_review
          return unless self.can_move_to_review?

          self.move_to_review
        end

        def set_verified
          self.move_to_verified if can_move_to_verified?
        end

        def type_unverified?
          !type_verified?
        end

        def type_verified?
          %w[verified attested].include? current_state
        end

        # Needs to be updated once we have the requirements for the rejected state
        def set_failed
          if self.reload.current_state == :rejected
            move_to_rejected
          else
            person = eligibility&.eligible&.find_person
            return move_to_negative_response_received unless person

            is_enrolled = person.families&.any? { |family| family.person_has_an_active_enrollment?(person) }
            (is_enrolled ? move_to_outstanding : move_to_negative_response_received)
          end
          return unless EnrollRegistry.feature_enabled?(:set_due_date_upon_response_from_hub)

          evidence_document_due = EnrollRegistry[:verification_document_due_in_days].item
          self.due_on = TimeKeeper.date_of_record + evidence_document_due.days
          self.due_on_type = 'response_from_hub'

          true
        end

        # Adds a new verification history record to the evidence with the specified action, update reason, and updated by user.
        #
        # @param action [String] The action performed on the evidence
        # @param update_reason [String] The reason for the update
        # @param updated_by [String] The user who performed the update
        def add_to_history(action, update_reason, updated_by)
          verification_histories.build(
            action: action,
            update_reason: update_reason,
            updated_by: updated_by
          )
        end

        # This ensures that the field is only set once and not overwritten.
        # Raises RuntimeError to not update the `due_date_extended_at` if it is already set.
        # This prevents accidental overwriting of the field after it has been set.
        #
        # @param value [DateTime] The date and time to set for the due_date_extended_at field
        #
        # @raise [RuntimeError] if the due_date_extended_at field is already set
        def due_date_extended_at=(value)
          if self.due_date_extended_at.blank?
            super(value)
          else
            # If the field is already set, do not change it.
            # This prevents overwriting the existing value.
            # You can also raise an error or log a message if needed.
            Rails.logger.warn(
              "Attempted to set due_date_extended_at when it is already set for evidence with id #{
                self.id}. Current value: #{self.due_date_extended_at}, Attempted value: #{value}"
            )

            raise 'due_date_extended_at is read-only and cannot be changed once set.'
          end
        end

        # Method is to retain current_state and due_on from the current evidence.
        # This is used in the context of the system generated applications like renewals and expired_rop.
        #
        # @param current_evidence [Eligibilities::V3::Evidence] The evidence from the current application
        #
        # @return [void]
        def retain_evidence_information(current_evidence)
          current_app = current_evidence.eligibility.eligible.application

          app_hbx_id = current_app.hbx_id
          app_type = case current_app.class
                     when IndividualMarket::Application
                       'qhp'
                     when FinancialAssistance::Application
                       'faa'
                     end

          pre_state = self.current_state
          new_state = current_evidence.current_state

          self.current_state = new_state
          self.add_to_history(
            'retain_evidence_info_on_renewal',
            "State is retained from the previous application with hbx_id: #{app_hbx_id}, app_type: #{app_type}, change from: #{pre_state} to: #{new_state}",
            'system'
          )

          return unless current_evidence.due_on.present?

          self.due_on = current_evidence.due_on
          self.add_to_history(
            'retain_evidence_info_on_renewal',
            "Due date is retained from the previous application with hbx_id: #{app_hbx_id}, app_type: #{app_type}, due_on: #{current_evidence.due_on}",
            'system'
          )
        end
      end
    end
  end
end
