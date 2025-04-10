# frozen_string_literal: true

module IndividualMarket
  # Represents demographic information for an individual market applicant
  #
  # @example Creating a new Demographics instance
  #   applicant.demographics.build(
  #     gender: 'male',
  #     dob: Date.new(1980, 1, 1),
  #     is_incarcerated: false,
  #     indian_tribe_member: false,
  #     language_code: 'en',
  #     ethnicity: ['hispanic_latino'],
  #     race: ['white']
  #   )
  #
  # @see IndividualMarket::Applicant The parent class that embeds this model
  class Demographics
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute applicant
    #   @return [IndividualMarket::Applicant] The applicant this demographics belongs to
    embedded_in :applicant, class_name: 'IndividualMarket::Applicant'

    # The encrypted Social Security Number of the applicant
    # @return [String]
    field :encrypted_ssn, type: String

    # Indicates if the applicant has no Social Security Number
    # @return [Boolean]
    field :no_ssn, type: Boolean

    # The gender of the applicant
    # @return [String]
    field :gender, type: String

    # The date of birth of the applicant
    # @return [Date]
    field :dob, type: Date

    # Indicates if the applicant is incarcerated
    # @return [Boolean]
    field :is_incarcerated, type: Boolean

    # @!attribute is_physically_disabled
    #   @return [Boolean] Indicates if the applicant is physically disabled
    field :is_physically_disabled, type: Boolean

    # Indicates if the applicant is a member of a recognized Indian tribe
    # @return [Boolean]
    field :indian_tribe_member, type: Boolean

    # The tribal identification number of the applicant if applicable
    # @return [String]
    field :tribal_id, type: String

    # The name of the tribe the applicant belongs to
    # @return [String]
    field :tribal_name, type: String

    # The state associated with the applicant's tribe
    # @return [String]
    field :tribal_state, type: String

    # The preferred language code of the applicant
    # @return [String]
    field :language_code, type: String

    # List of ethnicities the applicant identifies with
    # @return [Array]
    field :ethnicity, type: Array

    # List of races the applicant identifies with
    # @return [Array]
    field :race, type: Array
  end
end
