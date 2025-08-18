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
      dependent stepparent stepchild grandparent grandchild unrelated aunt_or_uncle nephew_or_niece grandchild grandparent
    ] + (EnrollRegistry.feature_enabled?(:mitc_relationships) ? %w[father_or_mother_in_law daughter_or_son_in_law brother_or_sister_in_law cousin domestic_partners_child parents_domestic_partner] : []).freeze

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

    private

    # Validates that source_id and relative_id are not the same
    # @return [void]
    def validate_different_source_and_relative
      errors.add(:relative_id, 'cannot be the same as source') if source_id == relative_id
    end
  end
end
