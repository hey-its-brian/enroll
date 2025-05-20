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

    CITIZEN_STATUS_KINDS = %w[
      us_citizen
      naturalized_citizen
      alien_lawfully_present
      lawful_permanent_resident
      undocumented_immigrant
      not_lawfully_present_in_us
      non_native_not_lawfully_present_in_us
      ssn_pass_citizenship_fails_with_SSA
      non_native_citizen
    ].freeze

    ACA_ELIGIBLE_CITIZEN_STATUS_KINDS = %w[
      us_citizen
      naturalized_citizen
      indian_tribe_member
    ].freeze

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

    # The codes of the tribes the applicant belongs to
    # @return [Array]
    field :tribe_codes, type: Array

    # The preferred language code of the applicant
    # @return [String]
    field :language_code, type: String

    # List of ethnicities the applicant identifies with
    # @return [Array]
    field :ethnicity, type: Array

    # List of races the applicant identifies with
    # @return [Array]
    field :race, type: Array

    # @!attribute citizen_status
    # @return [String] The citizen status of the applicant
    field :citizen_status, type: String

    validates :citizen_status,
              allow_blank: true,
              inclusion: { in: CITIZEN_STATUS_KINDS + ACA_ELIGIBLE_CITIZEN_STATUS_KINDS, message: "%{value} is not a valid citizen status" }

    # Validation for the presence of either no_ssn or encrypted_ssn
    validate :no_ssn_or_encrypted_ssn

    # Validation for the presence of no_ssn
    validates :no_ssn, inclusion: { in: [true, false] }

    private

    # Validates that either no_ssn or encrypted_ssn is present
    def no_ssn_or_encrypted_ssn
      errors.add(:base, 'One of no_ssn or encrypted_ssn must be present') if !no_ssn && encrypted_ssn.nil?
      errors.add(:base, 'Only one of no_ssn or encrypted_ssn must be present') if no_ssn && encrypted_ssn
    end
  end
end
