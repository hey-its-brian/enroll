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

      ROP_IN_PROGRESS_STATES = [:review, :outstanding, :rejected].freeze

      # Definition of all allowed state transitions
      # @return [Hash] Map of event names to transition rules
      # @example
      #   STATE_TRANSITIONS[:move_to_attested][:from] # Returns array of states from which :move_to_attested is allowed
      #   STATE_TRANSITIONS[:move_to_attested][:to]   # Returns the destination state after :move_to_attested event
      state_transitions do
        action :move_to_attested, from: [:initial, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified, :verified], to: :attested
        action :move_to_rejected, from: [:attested, :negative_response_received, :outstanding, :pending, :review, :unverified, :verified], to: :rejected
        action :move_to_negative_response_received, from: [:initial, :attested, :outstanding, :pending, :rejected, :review, :unverified, :verified], to: :negative_response_received
        action :move_to_unverified, from: [:initial, :attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :verified], to: :unverified
        action :move_to_outstanding, from: [:initial, :attested, :negative_response_received, :pending, :rejected, :review, :unverified, :verified], to: :outstanding
        action :move_to_verified, from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified], to: :verified
        action :move_to_review, from: [:attested, :negative_response_received, :outstanding, :pending, :rejected, :unverified, :verified], to: :review
        action :move_to_pending, from: [:initial, :attested, :negative_response_received, :outstanding, :rejected, :review, :unverified, :verified], to: :pending
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

        # Determines the appropriate state for evidence based on previous evidence and demographics changes.
        # For IVL evidences, if previous evidence is verified and demographics haven't changed,
        # the evidence is copied as verified. Otherwise, it transitions to an eligible state.
        #
        # @param hub_call [Boolean] Whether this is being called from a hub verification process (defaults to false)
        # @return [void]
        def determine_outstanding_state(call_type)
          hub_call = call_type != 'application_determination'
          ivl_evidence_keys = ::Eligibilities::V3::IndividualMarketEligibility::EVIDENCES
          prev_evidence = fetch_last_determined_evidence(hub_call: hub_call)

          if ivl_evidence_keys.include?(key.to_s) &&
             prev_evidence&.verified? &&
             demographics_changed?
            copied_verified
          else
            eligible_state(hub_call: hub_call)
          end
        end

        # Checks if the applicant's demographics have changed compared to the previous application.
        # Compares name, identity information, citizen status, and Indian tribe information.
        #
        # @return [Boolean] true if any demographics have changed, false otherwise
        def demographics_changed?
          prev_applicant = fetch_last_determined_applicant
          return false unless prev_applicant
          applicant = eligibility&.eligible
          applicant.name_changed?(prev_applicant) ||
            applicant.identity_info_changed?(prev_applicant) ||
            applicant.citizen_status_changed?(prev_applicant) ||
            applicant.indian_tribe_changed?(prev_applicant)
        end

        # Moves evidence to verified state when copying from previous application.
        # Used when previous evidence was verified and no demographics changes occurred.
        #
        # @return [void]
        def copied_verified
          return unless can_move_to_verified?

          move_to_verified
          build_verification_history(
            'copied_verified',
            "no demographics changes for the applicant",
            'system'
          )
        end

        # Determines the appropriate state transition based on whether ROP is in progress.
        # Routes to either ROP-specific logic or non-ROP logic.
        #
        # @return [void]
        def eligible_state(hub_call: false)
          if rop_in_progress?(hub_call: hub_call)
            rop_eligible_state(hub_call: hub_call)
          else
            non_rop_eligible_state
          end
        end

        def rop_in_progress?(hub_call: false)
          prev_evidence = fetch_last_determined_evidence(hub_call: hub_call)
          return false unless prev_evidence

          state = prev_evidence_state
          return false unless state

          ROP_IN_PROGRESS_STATES.include?(state.to_sym) &&
            prev_evidence.due_on.present? &&
            prev_evidence.due_on > TimeKeeper.date_of_record
        end

        def rop_eligible_state(hub_call: false)
          prev_evidence = fetch_last_determined_evidence(hub_call: hub_call)
          return unless prev_evidence

          case prev_evidence.current_state.to_s
          when 'review'
            copied_review(prev_evidence)
          when 'outstanding'
            copied_outstanding(prev_evidence)
          when 'rejected'
            copied_rejected(prev_evidence)
          else
            Rails.logger.warn("Unexpected state in rop_eligible_state: #{prev_evidence.current_state}")
          end
        end

        def non_rop_eligible_state
          person = eligibility&.eligible&.find_person
          return move_to_negative_response_received unless person

          is_enrolled = person.families&.any? { |family| family.person_has_an_active_enrollment?(person) }
          if is_enrolled
            return unless can_move_to_outstanding?

            move_to_outstanding
            if EnrollRegistry.feature_enabled?(:set_due_date_upon_response_from_hub)
              evidence_document_due = EnrollRegistry[:verification_document_due_in_days].item
              self.due_on = TimeKeeper.date_of_record + evidence_document_due.days
              self.due_on_type = 'response_from_hub'
            end
          else
            return unless can_move_to_negative_response_received?

            move_to_negative_response_received
          end
        end

        def prev_evidence_state
          family = fetch_family
          prev_evidence = fetch_last_determined_evidence
          return nil unless family && prev_evidence

          prev_evidence.current_state
        end

        def copied_review(prev_evidence)
          return unless can_move_to_review?

          move_to_review
          add_history_with_prev_due_on('copied_review', prev_evidence)
        end

        def copied_outstanding(prev_evidence)
          return unless can_move_to_outstanding?

          move_to_outstanding
          add_history_with_prev_due_on('copied_outstanding', prev_evidence)
        end

        def copied_rejected(prev_evidence)
          return unless can_move_to_rejected?

          move_to_rejected
          add_history_with_prev_due_on('copied_rejected', prev_evidence)
        end

        # Sets the due date from previous evidence and adds verification history.
        #
        # @param action [String] The action being performed
        # @param prev_evidence [Evidence] The previous evidence to copy due date from
        # @return [void]
        def add_history_with_prev_due_on(action, prev_evidence)
          self.due_on = prev_evidence.due_on
          build_verification_history(
            action,
            "copied state from previous application",
            'system'
          )
        end

        def application_type(application)
          app_class = application.class
          if app_class == IndividualMarket::Application
            'qhp'
          elsif app_class == FinancialAssistance::Application
            'faa'
          else
            raise "Unknown application type: #{app_class}"
          end
        end

        def fetch_applicant_hbx_id(applicant)
          if application_type(applicant.application) == 'qhp'
            applicant.hbx_id
          else
            applicant.person_hbx_id
          end
        end

        def fetch_family
          @fetch_family ||= eligibility&.eligible&.application&.family
        end

        def current_app_id
          @current_app_id ||= eligibility&.eligible&.application&.id
        end

        def fetch_last_determined_application(hub_call: false)
          family = fetch_family
          return nil unless family

          @fetch_last_determined_application ||= if hub_call
                                                   eligibility&.eligible&.application
                                                 else
                                                   family.fetch_last_determined_application_from(current_app_id, 2025)
                                                 end
        end

        def fetch_last_determined_applicant(hub_call: false)
          family_member_id = eligibility.eligible.family_member_id
          return nil unless family_member_id

          application = fetch_last_determined_application(hub_call: hub_call)
          return nil unless application

          @fetch_last_determined_applicant ||= application.applicants&.detect do |applicant|
            applicant.family_member_id == family_member_id
          end
        end

        def fetch_last_determined_evidence(hub_call: false)
          applicant = fetch_last_determined_applicant(hub_call: hub_call)
          return nil unless applicant

          target_eligibility = applicant.individual_market_eligibility
          return nil unless target_eligibility

          @fetch_last_determined_evidence ||= target_eligibility.evidences&.where(key: key)&.first
        end

        # Adds a new verification history record to the evidence with the specified action, update reason, and updated by user. (not persisted)
        #
        # @param action [String] The action performed on the evidence
        # @param update_reason [String] The reason for the update
        # @param updated_by [String] The user who performed the update
        def build_verification_history(action, update_reason, updated_by)
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
          self.build_verification_history(
            'retain_evidence_info_on_renewal',
            "State is retained from the previous application with hbx_id: #{app_hbx_id}, app_type: #{app_type}, change from: #{pre_state} to: #{new_state}",
            'system'
          )

          return unless current_evidence.due_on.present?

          self.due_on = current_evidence.due_on
          self.build_verification_history(
            'retain_evidence_info_on_renewal',
            "Due date is retained from the previous application with hbx_id: #{app_hbx_id}, app_type: #{app_type}, due_on: #{current_evidence.due_on}",
            'system'
          )
        end
      end
    end
  end
end
