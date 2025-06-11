# frozen_string_literal: true

# A model representing a person's name components in the system.
# This class is embedded within different types of parent models using a polymorphic
# association, allowing any model to have name information without duplicating code.
#
# @example Embedding in a IndividualMarket::Applicant model
#   class IndividualMarket::Applicant
#     include Mongoid::Document
#     include Mongoid::Timestamps
#
#     embeds_one :person_name, class_name: 'PersonName', as: :person_nameable
#   end
#
# @example Embedding in a Person model
#   class Person
#     include Mongoid::Document
#     include Mongoid::Timestamps
#
#     embeds_many :names, class_name: 'PersonName', as: :person_nameable
#   end
#
# @note The polymorphic association is used here because multiple models
#   (like Person, Applicant, Employee, etc.) might need to store name information.
#   The polymorphic approach allows any model to embed this document without
#   having to create separate name classes for each parent model type.
class PersonName
  include Mongoid::Document
  include Mongoid::Timestamps

  SUFFIX_OPTIONS = [
    'Jr.', 'Sr.', 'II', 'III', 'IV', 'V'
  ].freeze

  # Defines the polymorphic relationship with the parent document
  # This allows PersonName to be embedded in any model that sets itself as :person_nameable
  embedded_in :person_nameable, polymorphic: true

  # @!attribute given_name
  #   @return [String] The person's given name
  field :given_name, type: String

  # @!attribute middle_name
  #   @return [String] The person's middle name
  field :middle_name, type: String

  # @!attribute family_name
  #   @return [String] The person's family name
  field :family_name, type: String

  # @!attribute name_sfx
  #   @return [String] The suffix of the person's name (e.g., "Jr.", "Sr.", "III")
  field :name_sfx, type: String

  # @!attribute name_pfx
  #   @return [String] The prefix of the person's name (e.g., "Dr.", "Mr.", "Mrs.")
  field :name_pfx, type: String

  # @!attribute alternate_name
  #   @return [String] An alternate name or a nickname for the person, if any
  field :alternate_name, type: String

  validates :name_sfx,
            allow_blank: true,
            inclusion: { in: PersonName::SUFFIX_OPTIONS, message: "%{value} is not a valid suffix" }

  # Combines all name components into a full name representation
  #
  # @return [String] The complete name with all present components joined with spaces
  def full_name
    return @full_name if defined?(@full_name)

    @full_name = [name_pfx, given_name, middle_name, family_name, name_sfx].compact.join(' ')
  end

  # Creates a copy of this person name for a new nameable entity
  #
  # @param [Object] new_person_nameable The object that will embed the cloned person name
  # @return [PersonName] The newly created person name with identical attributes
  # @example Clone a person name to a new applicant
  #   existing_name.copy_person_name(new_applicant)
  def copy_person_name(new_person_nameable)
    new_person_nameable.build_person_name(
      given_name: given_name,
      middle_name: middle_name,
      family_name: family_name,
      name_sfx: name_sfx,
      name_pfx: name_pfx,
      alternate_name: alternate_name
    )
  end
end
