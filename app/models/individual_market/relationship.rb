# frozen_string_literal: true

module IndividualMarket
  # Represents a familial or legal relationship between two applicants within an application
  # Each relationship connects two applicants, a source and a relative, with a specific kind
  # Source is kind of relative. Example: A is parent of B where A is source and B is relative.
  #
  # @example Create a relationship between a parent and child
  #   application.relationships.build(kind: 'parent', source_id: source_member.id, relative_id: relative_member.id)
  class Relationship
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [rw] application
    #   @return [IndividualMarket::Application] The application this relationship belongs to
    embedded_in :application, class_name: 'IndividualMarket::Application'

    # @!attribute [rw] kind
    #   @return [String] The type of relationship between source and relative applicants
    field :kind, type: String

    # @!attribute [rw] source_id
    #   @return [BSON::ObjectId] The ID of the source applicant in the relationship
    field :source_id, type: BSON::ObjectId

    # @!attribute [rw] relative_id
    #   @return [BSON::ObjectId] The ID of the relative applicant in the relationship
    field :relative_id, type: BSON::ObjectId

    # @!attribute [r] RELATIONSHIP_KINDS
    # @return [Array<String>] List of valid relationship kinds
    RELATIONSHIP_KINDS = %w[
      spouse child parent sibling domestic_partner guardian ward sponsored_dependent
      dependent stepparent stepchild grandparent grandchild
    ].freeze

    # @!attribute [r] validations
    # @note The model validates that kind is present and included in RELATIONSHIP_KINDS
    # @note The model validates that source_id and relative_id are present
    validates :kind, presence: true, inclusion: { in: RELATIONSHIP_KINDS }
    validates :source_id, presence: true
    validates :relative_id, presence: true
    validate :validate_different_source_and_relative

    # Finds the source applicant in the relationship
    # @return [IndividualMarket::Applicant, nil] The source applicant or nil if not found
    # @note This method memoizes the result to avoid repeated database queries
    def source
      return @source if defined?(@source)

      @source = application.applicants.where(id: source_id).first
    end

    # Finds the relative applicant in the relationship
    # @return [IndividualMarket::Applicant, nil] The relative applicant or nil if not found
    # @note This method memoizes the result to avoid repeated database queries
    def relative
      return @relative if defined?(@relative)

      @relative = application.applicants.where(id: relative_id).first
    end

    # Creates a copy of this relationship in a new application
    #
    # @param [IndividualMarket::Application] new_app The new application where the relationship will be created
    # @return [IndividualMarket::Relationship] The newly created relationship
    # @example Copy a relationship to a new application
    #   relationship.copy_relationship(new_application)
    def copy_relationship(new_app)
      new_app.relationships.build(
        kind: kind,
        source_id: fetch_matching_applicant_id(new_app, source_id),
        relative_id: fetch_matching_applicant_id(new_app, relative_id)
      )
    end

    private

    # Finds the matching applicant ID in the new application based on family_member_id
    #
    # @param [IndividualMarket::Application] new_app The new application to search in
    # @param [BSON::ObjectId] old_id The ID of the applicant in the original application
    # @return [BSON::ObjectId] The ID of the matching applicant in the new application
    # @raise [ArgumentError] If the original ID is nil, applicant not found, or no matching applicant exists
    def fetch_matching_applicant_id(new_app, old_id)
      raise ArgumentError, "Missing source_id or relative_id for relationship with id: #{id} for application with id: #{application.id}" if old_id.nil?

      appli = application.applicants.where(id: old_id).first
      raise ArgumentError, "Applicant with id: #{old_id} not found in application with id: #{application.id}" if appli.nil?

      new_appli = new_app.applicants.where(family_member_id: appli.family_member_id).first
      raise ArgumentError, "No matching applicant found in new application for family_member_id: #{appli.family_member_id}" if new_appli.nil?

      new_appli.id
    end

    # Validates that source_id and relative_id are not the same
    # @return [void]
    def validate_different_source_and_relative
      errors.add(:relative_id, 'cannot be the same as source') if source_id == relative_id
    end
  end
end
