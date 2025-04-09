# frozen_string_literal: true

module IndividualMarket
  # An application for individual market coverage that extends the base Sbm::Application
  #
  # @example Creating a new individual market application type using _type field
  #   family.applications.build(_type: 'IndividualMarket::Application')
  #
  # @see Sbm::Application The parent class following Single Table Inheritance pattern
  class Application < Sbm::Application

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

    private

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
