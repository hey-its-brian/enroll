# frozen_string_literal: true

module IndividualMarket
  # An application for individual market coverage that extends the base Sbm::Application
  #
  # @example Creating a new individual market application type using _type field
  #   family.applications.build(_type: 'IndividualMarket::Application')
  #
  # @see Sbm::Application The parent class following Single Table Inheritance pattern
  class Application < Sbm::Application
    include Eligibilities::Visitors::Visitable

    # @!attribute applicants
    # @return [Array<IndividualMarket::Applicant>] Collection of individuals within the application
    embeds_many :applicants, class_name: 'IndividualMarket::Applicant', cascade_callbacks: true

    # @!attribute relationships
    # @return [Array<IndividualMarket::Relationship>] Collection of relationships between applicants
    embeds_many :relationships, class_name: 'IndividualMarket::Relationship', cascade_callbacks: true

    # @!attribute attestation
    # @return [IndividualMarket::Attestation] Attestation for the application
    embeds_one :attestation, class_name: 'IndividualMarket::Attestation', cascade_callbacks: true

    # A replacement model for WorkflowStateTransition.
    # In future, we will use has_chronicle that could potentially include both versions of the current model and its state history.
    # This is the reason why the state_histories association is added here and not in the parent class.
    #
    # @!attribute state_histories
    #   @return [Array<StateHistory>] The history of state transitions for this eligibility
    embeds_many :state_histories, class_name: 'Eligibilities::V3::StateHistory', as: :status_trackable, cascade_callbacks: true

    # Validates that no duplicate relationships exist within the application
    # @note A duplicate relationship is defined as having the same source_id and relative_id
    # @example Validation failing with duplicate relationships
    #   application = IndividualMarket::Application.new
    #   application.relationships.build(source_id: '123', relative_id: '456')
    #   application.relationships.build(source_id: '123', relative_id: '456')
    #   application.valid? # => false
    #   application.errors[:relationships] # => ["contains duplicate relationships (same source and relative)"]
    # @return [void]
    validate :no_duplicate_relationships

    # Validates that the application has one applicant marked as primary
    # @note An application must have exactly one primary applicant
    # @example Validation failing with no primary applicant
    #   application = IndividualMarket::Application.new
    #   application.applicants.build(is_primary_applicant: false)
    #   application.valid? # => false
    #   application.errors[:applicants] # => ["must have exactly one primary applicant"]
    # @return [void]
    validate :only_one_primary_applicant

    # @!attribute ORIGIN_KINDS
    # @return [Array<Symbol>] Collection of all possible origin kinds
    ORIGIN_KINDS = %i[admin assister broker data_import migration system user].freeze

    # @!attribute GENERATION_REASONS
    # @return [Array<Symbol>] Collection of all possible generation reasons
    GENERATION_REASONS = %i[manual renewal rop_expiration].freeze

    # Validates the origin field to ensure it is a valid kind
    validates :origin, inclusion: { in: ORIGIN_KINDS }

    # Validates the generation_reason field to ensure it is a valid reason
    validates :generation_reason, inclusion: { in: GENERATION_REASONS }

    # Validates the assistance_year field to ensure it is present and greater than or equal to 2025
    # @note The year 2025 is used as a minimum value for the assistance year
    validates :assistance_year, presence: true, numericality: { greater_than_or_equal_to: 2025 }

    # @!attribute effective_on
    # @return [Date] The date the application is effective
    field :effective_on, type: Date

    # @!attribute submitted_at
    # @return [DateTime] The date and time the application was submitted
    field :submitted_at, type: DateTime

    # @!attribute assistance_year
    # @return [Integer] The year for which the application is requesting assistance
    field :assistance_year, type: Integer

    # @!attribute predecessor_id
    # @return [BSON::ObjectId] The ID of the application that this application replaces
    field :predecessor_id, type: BSON::ObjectId

    # Indicates if the application was created by a user or system process
    # @!attribute origin
    # @return [Symbol] The source that created this application
    # @option user [Symbol] Created by a user through the UI
    # @option system [Symbol] Created automatically by the system
    # @option admin [Symbol] Created by an admin user
    # @option data_import [Symbol] Created through a data import process
    # @option migration [Symbol] Created by a migration script
    field :origin, type: Symbol

    # Specifies the reason for system-generated applications
    # @!attribute generation_reason
    # @return [Symbol] The specific reason why the system generated this application
    # @option manual [Symbol] Manually created (default for user applications)
    # @option rop_expiration [Symbol] Created due to Reasonable Opportunity Period (ROP) expiration
    # @option renewal [Symbol] Created as part of the annual renewal process
    field :generation_reason, type: Symbol

    # -- State Machine Start --

    # Replacement for aasm_state. Tells the current state of the eligibility.
    # @!attribute current_state
    # @return [Symbol] The current state of the application
    field :current_state, type: Symbol, default: :initial

    # @!attribute is_renewal
    # @return [Boolean] Indicates if the application is a renewal application
    # @note This field is used to track if the application is a renewal of a previous application
    field :is_renewal, type: Boolean, default: false

    # All possible states for an application
    # @!attribute ALL_STATES
    # @return [Array<Symbol>] Collection of all possible states
    # @option initial [Symbol] A state that is identified as in progress
    # @option submission_failed [Symbol] A state that failed validation for submission (missing information)
    # @option submitted [Symbol] A state that is submitted
    # @option determination_failed [Symbol] A state that cannot be determined because of an error or missing information
    # @option determined [Symbol] A state that is determined
    # @option expired [Symbol] A state that is expired. This could happen at any point during the process.
    #                          Examples: 1) An in progress application exists and the user creates a new application,
    #                          the old application will be marked as expired.
    #                          2) FUTURE USE CASE: All applications that are older than specific number of years could be marked as expired.
    ALL_STATES = %i[
      initial
      submission_failed
      submitted
      determination_failed
      determined
      expired
    ].freeze

    # Defines valid state transitions for the state machine
    # @!attribute STATE_TRANSITIONS
    # @return [Hash] Mapping of events to their from states and to states
    STATE_TRANSITIONS = {
      reset: {
        from: [:submission_failed],
        to: :initial
      },
      failed_submission: {
        from: [:initial],
        to: :submission_failed
      },
      submit: {
        from: [:initial, :submission_failed],
        to: :submitted
      },
      failed_determination: {
        from: [:submitted],
        to: :determination_failed
      },
      determine: {
        from: [:submitted],
        to: :determined
      },
      expire: {
        from: [:initial, :submission_failed, :submitted, :determination_failed, :determined],
        to: :expired
      }
    }.freeze

    STATE_TRANSITIONS.each_key do |event|
      # Dynamically define may_*? methods for each event to check if transition is allowed
      define_method("may_#{event}?") do
        STATE_TRANSITIONS[event][:from].include?(current_state)
      end

      # Dynamically define event methods for state transitions
      define_method(event) do |comment = nil, reason = nil|
        transition_state(event, comment, reason)
      end
    end

    # Finds and returns the applicant who is marked as the primary applicant
    #
    # @return [FamilyMember] The primary applicant associated with this application
    def primary_applicant
      applicants.where(is_primary_applicant: true).first
    end

    # Finds and returns the applicants who are not marked as the primary applicant
    #
    # @return [Array<FamilyMember>] The non-primary applicants associated with this application
    def non_primary_applicants
      applicants.where(is_primary_applicant: false)
    end

    # Defines the specific policy class for the application model as the application policy already exists
    def policy_class
      QhpApplicationPolicy
    end

    # Accepts a visitor to perform operations on each applicant
    #
    # @param visitor [Object] The visitor object that will perform operations on each applicant
    def accept(visitor)
      applicants.collect{|applicant| applicant.accept(visitor) }
    end

    private

    # Validates that there is exactly one primary applicant in the application if there are any applicants
    def only_one_primary_applicant
      return if applicants.empty?

      # Select applicants who are marked as primary
      primary_applicants = applicants.select(&:is_primary_applicant)

      # Check if there is exactly one primary applicant
      errors.add(:applicants, 'must have exactly one primary applicant') if primary_applicants.size != 1
    end

    # Handles state transitions with validation and state history tracking
    # @param event [Symbol] The event triggering the state transition
    # @param comment [String, nil] Optional comment about why the state changed
    # @param reason [String, nil] Optional reason code for the state change
    # @raise [ArgumentError] When current_state is invalid or transition is not allowed
    # @return [void]
    def transition_state(event, comment = nil, reason = nil)
      raise(ArgumentError, "Invalid from_state: #{current_state}") if ALL_STATES.exclude?(current_state)

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

    # -- State Machine End --

    # Validates that there are no duplicate relationships with the same source and relative
    def no_duplicate_relationships
      # Group relationships by source_id and relative_id
      grouped = relationships.group_by { |rel| [rel.source_id, rel.relative_id] }

      # Check for duplicates (any group with more than one element)
      duplicates = grouped.select { |_, relations| relations.size > 1 }

      # If duplicates exist, add an error
      errors.add(:relationships, 'contains duplicate relationships (same source and relative)') if duplicates.any?
    end
  end
end
