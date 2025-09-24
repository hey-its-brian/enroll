# frozen_string_literal: true

module Eligibilities
  module V3
    # Evidence utility class for AptcCsr and IndividualMarket eligibility
    # Module is used to include the common methods, fields, validations, associations etc of all the evidences related to AptcCsr and IndividualMarket eligibility.
    module EvidenceUtils
      extend ActiveSupport::Concern
      include StateMachine

      OUTSTANDING_STATUSES = %i[outstanding rejected review].freeze

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
        action :move_to_attested, from: [:initial, :negative_response_received, :outstanding, :pending, :rejected, :review, :unverified], to: :attested
        action :move_to_rejected, from: [:attested, :negative_response_received, :outstanding, :pending, :review, :unverified, :verified], to: :rejected
        action :move_to_negative_response_received, from: [:initial, :attested, :outstanding, :pending, :rejected, :review, :unverified, :verified], to: :negative_response_received
        action :move_to_unverified, from: [:initial, :attested, :negative_response_received, :outstanding, :pending, :rejected, :review, :verified], to: :unverified
        action :move_to_outstanding, from: [:initial, :attested, :negative_response_received, :pending, :rejected, :review, :unverified, :verified], to: :outstanding
        action :move_to_verified, from: [:negative_response_received, :outstanding, :pending, :rejected, :review, :unverified], to: :verified
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

          # For the migrated data, created at is same for all the migrated verification histories
          # due to this verification_histories.newest.first is fetching first inserted record instead of last
          # Since the history objects are stored in order it was built
          # Fetching the last record from the verification_histories should resolve the issue
          @latest_verification_history = verification_histories.last
        end

        # Returns the most recent rejected verification history record
        #
        # This method retrieves the newest rejected verification history record for this eligibility.
        # The result is memoized to avoid repeated database queries.
        #
        # @return [StateHistory, nil] The most recent rejected verification history record, or nil if none exists
        def latest_rejected_verification_history
          return @latest_rejected_verification_history if defined?(@latest_rejected_verification_history)

          @latest_rejected_verification_history = verification_histories.where(action: 'return_for_deficiency').last
        end

        def determine_outstanding_due_on_date(call_type)
          if call_type == 'bulk_call'
            schedule_verification_due_on_for_bulk_call
          else
            schedule_verification_due_on
          end
        end

        def schedule_verification_due_on
          verification_document_due = EnrollRegistry[:verification_document_due_in_days].item
          TimeKeeper.date_of_record + verification_document_due.days
        end

        def schedule_verification_due_on_for_bulk_call
          verification_document_due = EnrollRegistry[:bulk_call_verification_due_in_days].item
          self.due_on_type = 'bulk_response_from_hub'
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

          assign_attributes(verification_outstanding: false, is_satisfied: true)
          self.move_to_negative_response_received
        end

        def mark_as_verified
          return unless self.can_move_to_verified?

          assign_attributes(verification_outstanding: false, is_satisfied: true, due_on: nil)
          self.move_to_verified
        end

        def mark_as_unverified
          return unless self.can_move_to_unverified?

          assign_attributes(verification_outstanding: true, is_satisfied: false, due_on: nil)
          self.move_to_unverified
        end

        def mark_as_attested
          return unless self.can_move_to_attested?

          assign_attributes(verification_outstanding: false, is_satisfied: true, due_on: nil)
          self.move_to_attested
        end

        def mark_as_rejected
          return unless self.can_move_to_rejected?

          assign_attributes(verification_outstanding: true, is_satisfied: false)
          due_on = self.due_on || schedule_verification_due_on
          self.due_on = due_on unless self.current_state == 'review'
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
          ivl_evidence_keys = ::Eligibilities::V3::IndividualMarketEligibility::EVIDENCES
          prev_evidence = fetch_last_determined_evidence(call_type)

          if ivl_evidence_keys.include?(key.to_s) &&
             evidence_verified?(prev_evidence) &&
             demographics_changed?(call_type)
            copied_verified(prev_evidence, call_type)
          else
            eligible_state(call_type)
          end
        end

        # Checks if the applicant's demographics have changed compared to the previous application.
        # Compares name, identity information, citizen status, and Indian tribe information.
        #
        # @return [Boolean] true if any demographics have changed, false otherwise
        def demographics_changed?(call_type)
          prev_applicant = fetch_last_determined_applicant(call_type)
          return false unless prev_applicant
          applicant = eligibility&.eligible
          applicant.name_changed?(prev_applicant) ||
            applicant.identity_info_changed?(prev_applicant) ||
            applicant.citizen_status_changed?(prev_applicant) ||
            applicant.indian_tribe_changed?(prev_applicant)
        end

        # Determines the appropriate state transition based on whether ROP is in progress.
        # Routes to either ROP-specific logic or non-ROP logic.
        #
        # @return [void]
        def eligible_state(call_type)
          if rop_in_progress?(call_type)
            rop_eligible_state(call_type)
          else
            non_rop_eligible_state(call_type)
          end
        end

        def rop_in_progress?(call_type)
          prev_evidence = fetch_last_determined_evidence(call_type)
          return false unless prev_evidence

          state = prev_evidence_state(call_type)
          return false unless state

          ROP_IN_PROGRESS_STATES.include?(state.to_sym) &&
            prev_evidence.due_on.present? &&
            prev_evidence.due_on > TimeKeeper.date_of_record
        end

        def rop_eligible_state(call_type)
          prev_evidence = fetch_last_determined_evidence(call_type)
          prev_evidence_state = prev_evidence_state(call_type)
          return unless prev_evidence_state

          case prev_evidence_state.to_s
          when 'review'
            copied_review(prev_evidence, call_type)
          when 'outstanding'
            copied_outstanding(prev_evidence, call_type)
          when 'rejected'
            copied_rejected(prev_evidence, call_type)
          else
            Rails.logger.warn("Unexpected state in rop_eligible_state: #{prev_evidence.current_state}")
          end
        end

        # Non-ROP eligible state logic
        #  When evidence is in outstanding/review/rejected and due date is not in future
        #  # if enrolled, evidence should be in outstanding and new due date is assigned
        #  # if not enrolled, evidence should be in NRR and no due date
        #  When evidence is in NRR
        #  # if enrolled, evidence should be in outstanding and new due date is assigned
        #  # if not enrolled, evidence should be in NRR and no due date
        def non_rop_eligible_state(call_type)
          eligible = eligibility&.eligible
          person = eligible&.find_person
          return mark_as_negative_response_received unless person

          is_enrolled = enrolled_for_non_rop?(eligible, person)

          if is_enrolled
            self.due_on = determine_outstanding_due_on_date(call_type)
            assign_attributes(verification_outstanding: true, is_satisfied: false)

            # do not update state if evidence is alive_evidence and current_state is rejected
            return if self.key == :alive_evidence && self.current_state == 'rejected'

            move_to_outstanding if can_move_to_outstanding?
          else
            mark_as_negative_response_received
          end
        end

        def enrolled_for_non_rop?(eligible, person)
          if Eligibilities::V3::AptcCsrEligibility::EVIDENCES.include?(key)
            family = fetch_family
            enrollments = HbxEnrollment.where(:aasm_state.in => HbxEnrollment::ENROLLED_STATUSES, family_id: family.id)
            eligible.enrolled_in_any_aptc_csr_enrollments?(enrollments)
          else
            person.families&.any? { |f| f.person_has_an_active_enrollment?(person) }
          end
        end

        def prev_evidence_state(call_type)
          prev_evidence = fetch_last_determined_evidence(call_type)
          return nil unless prev_evidence

          fetch_evidence_prev_state(prev_evidence)
        end

        def fetch_evidence_prev_state(prev_evidence)
          @fetch_evidence_prev_state ||= if prev_evidence == self
            # since for call hub we move evidence into pending before the request, and
            # prev state is needed to determine the current state.
                                           prev_evidence.state_histories.last.from_state
                                         else
                                           prev_evidence.current_state
                                         end
        end

        def evidence_verified?(prev_evidence)
          return false unless prev_evidence
          fetch_evidence_prev_state(prev_evidence).to_s == 'verified'
        end

        # should be used only for copied state methods
        # since it has a different logic when prev_evidence is not self
        def fetch_prev_state_for_history(prev_evidence)
          @fetch_prev_state_for_history ||= if prev_evidence == self
                                              prev_evidence.state_histories.last.from_state
                                            else
                                              current_state
                                            end
        end

        # Moves evidence to verified state when copying from previous application.
        # Used when previous evidence was verified and no demographics changes occurred.
        #
        # @return [void]
        def copied_verified(prev_evidence, call_type)
          prev_state = fetch_prev_state_for_history(prev_evidence)
          mark_as_verified if can_move_to_verified?
          message = build_copied_message(prev_state, call_type)
          build_verification_history('copied_verified', message, 'system')
        end

        def copied_review(prev_evidence, call_type)
          prev_state = fetch_prev_state_for_history(prev_evidence)
          move_to_review if can_move_to_review?
          add_history_with_prev_due_on('copied_review', prev_evidence, prev_state, call_type)
        end

        def copied_outstanding(prev_evidence, call_type)
          prev_state = fetch_prev_state_for_history(prev_evidence)
          assign_attributes(verification_outstanding: true, is_satisfied: false)
          move_to_outstanding if can_move_to_outstanding?
          add_history_with_prev_due_on('copied_outstanding', prev_evidence, prev_state, call_type)
        end

        def copied_rejected(prev_evidence, call_type)
          prev_state = fetch_prev_state_for_history(prev_evidence)
          assign_attributes(verification_outstanding: true, is_satisfied: false)
          move_to_rejected if can_move_to_rejected?
          add_history_with_prev_due_on('copied_rejected', prev_evidence, prev_state, call_type)
        end

        # Sets the due date from previous evidence and adds verification history.
        #
        # @param action [String] The action being performed
        # @param prev_evidence [Evidence] The previous evidence to copy due date from
        # @return [void]
        def add_history_with_prev_due_on(action, prev_evidence, prev_state, call_type)
          self.due_on = prev_evidence.due_on if prev_evidence.due_on.present?
          self.due_date_extended_at = prev_evidence.due_date_extended_at if prev_evidence.due_date_extended_at.present?
          message = build_copied_message(prev_state, call_type)
          build_verification_history(action, message, 'system')
        end

        # Generates a message describing the state transition and data copied
        #
        # @param prev_state [Symbol] The previous state before transition
        # @param call_type [String] The type of call
        # @return [String, nil] The generated message or nil if application not found
        def build_copied_message(prev_state, call_type)
          application = fetch_last_determined_application(call_type)
          return nil if application.nil?

          app_hbx_id = application.hbx_id
          app_type = application_type(application)

          base_message = "State updated from #{prev_state} to #{self.current_state}"
          app_info = "from previous application #{app_hbx_id} application type #{app_type}"

          if due_on.present? && due_date_extended_at.present?
            "#{base_message}, due date of #{due_on} copied, and #{due_date_extended_at} automatic due date extended at copied #{app_info} due to active ROP."
          elsif due_on.present?
            "#{base_message} and due date of #{due_on} copied #{app_info} due to active ROP."
          else
            "#{base_message} based on previous application #{app_hbx_id} application type #{app_type} because there were no demographic changes for the person."
          end
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

        def fetch_last_determined_application(call_type)
          family = fetch_family
          return nil unless family

          @fetch_last_determined_application ||= if ['hub_call', 'bulk_call'].include?(call_type)
                                                   eligibility&.eligible&.application
                                                 else
                                                   family.fetch_last_determined_application_from(current_app_id, 2025)
                                                 end
        end

        def fetch_last_determined_applicant(call_type)
          family_member_id = eligibility.eligible.family_member_id
          return nil unless family_member_id

          application = fetch_last_determined_application(call_type)
          return nil unless application

          @fetch_last_determined_applicant ||= application.applicants&.detect do |applicant|
            applicant.family_member_id == family_member_id
          end
        end

        def fetch_last_determined_evidence(call_type)
          applicant = fetch_last_determined_applicant(call_type)
          return nil unless applicant

          target_eligibility = applicant.eligibilities.detect {|eli| eli.key == eligibility.key }
          return nil unless target_eligibility.present?

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
          if self.due_date_extended_at.blank? || value.blank?
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

          state_and_date_change_text = if current_evidence.due_on.present? && OUTSTANDING_STATUSES.include?(new_state.to_sym)
                                         self.due_on = current_evidence.due_on
                                         "State updated from #{pre_state} to #{new_state} " \
                                                                      "and due date of #{current_evidence.due_on} copied " \
                                                                      "from previous application #{app_hbx_id} application type #{app_type} " \
                                                                      "due to annual eligibility redetermination."
                                       else
                                         "State updated from #{pre_state} to #{new_state} " \
                                                                      "copied from previous application #{app_hbx_id} application type #{app_type} " \
                                                                      "due to annual eligibility redetermination."
                                       end

          self.build_verification_history(
            'retain_evidence_info_on_renewal',
            state_and_date_change_text,
            'system'
          )
        end
      end
    end
  end
end
