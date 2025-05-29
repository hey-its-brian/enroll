# frozen_string_literal: true

module IndividualMarket
  # An Applicant represents an individual member within an insurance application.
  # Each application can have multiple applicants, typically representing family members
  # or other members of a household seeking insurance coverage.
  #
  # @example Create an applicant with a name
  #   application = IndividualMarket::Application.new
  #   applicant = application.applicants.build
  #   applicant.build_person_name(first_name: 'John', last_name: 'Doe')
  #
  # @note Applicants contain demographic information and eligibility determinations
  #       that are used throughout the enrollment process.
  class Applicant
    include Mongoid::Document
    include Mongoid::Timestamps
    include Config::AcaModelConcern
    include Eligibilities::Visitors::Visitable

    # @!attribute application
    #   @return [IndividualMarket::Application] The application this applicant belongs to
    embedded_in :application, class_name: 'IndividualMarket::Application'

    # @!attribute person_name
    #   @return [PersonName] The name of the applicant
    embeds_one :person_name, class_name: 'PersonName', as: :person_nameable, cascade_callbacks: true

    # Ideally we want to use DemographicsGroup here but the DemographicsGroup by updating it to include Race, Ethnicity, and Gender information.
    # We have upgraded the DemographicsGroup to include these in dchbx_enroll.
    # We cannot use the DemographicsGroup from dchbx_enroll as it is not backward compatible with the existing version of Race and Ethnicity.
    #
    # @!attribute demographics
    #   @return [IndividualMarket::Demographics] Demographic information about the applicant
    embeds_one :demographics, class_name: 'IndividualMarket::Demographics', cascade_callbacks: true

    # An eligibility can be individual_market_eligibility, magi_medicaid_eligibility, aptc_csr_eligibility, or osse_shop_eligibility
    #
    # @!attribute eligibilities
    #   @return [Array<Eligibilities::V3::Eligibility>] Collection of different eligibility determinations for this applicant
    embeds_many :eligibilities, class_name: 'Eligibilities::V3::Eligibility', as: :eligible, cascade_callbacks: true

    # @!attribute immigration_information
    #   @return [IndividualMarket::ImmigrationInformation] Applicant's immigration information if applicable
    embeds_one :immigration_information, class_name: 'IndividualMarket::ImmigrationInformation', cascade_callbacks: true

    # @!attribute addresses
    #   @return [Array<Locations::Address>] Collection of addresses associated with this applicant
    embeds_many :addresses, class_name: 'Locations::Address', as: :addressable, cascade_callbacks: true

    # @!attribute family_member_id
    #   @return [BSON::ObjectId] The ID of the family member associated with this applicant
    field :family_member_id, type: BSON::ObjectId

    # @!attribute is_primary_applicant
    #   @return [Boolean] Indicates if this applicant is the primary applicant for the application
    #   @note Only one applicant can be marked as the primary applicant in an application
    field :is_primary_applicant, type: Boolean

    # @!attribute address_same_as_primary
    #   @return [Boolean] Indicates if this applicant's address is the same as the primary applicant's address
    field :address_same_as_primary, type: Boolean

    # @!attribute is_applying_coverage
    #   @return [Boolean] Indicates if this applicant is applying for coverage
    field :is_applying_coverage, type: Boolean

    # @!attribute is_homeless
    #   @return [Boolean] Indicates if this applicant is homeless
    field :is_homeless, type: Boolean

    # @!attribute age_off_excluded
    # @return [Boolean] Indicates if this applicant is should be kept on their parent's plan when they are 26+
    field :age_off_excluded, type: Boolean

    validate :unique_eligibilities

    accepts_nested_attributes_for :person_name, :demographics, :eligibilities, :immigration_information, :addresses

    # Finds and returns the family member associated with this applicant
    #
    # @return [FamilyMember] The family member associated with this applicant
    def family_member
      return @family_member if defined?(@family_member)

      @family_member = FamilyMember.find(family_member_id)
    end

    def aptc_csr_eligibility
      return @aptc_csr_eligibility if defined?(@aptc_csr_eligibility)

      @aptc_csr_eligibility = eligibilities.where(_type: 'Eligibilities::V3::AptcCsrEligibility').first
    end

    def individual_market_eligibility
      return @individual_market_eligibility if defined?(@individual_market_eligibility)

      @individual_market_eligibility = eligibilities.where(_type: 'Eligibilities::V3::IndividualMarketEligibility').first
    end

    # @!attribute age_on
    # @return [Integer] The age of the applicant on a given date
    def age_on(date)
      dob = self.demographics.dob
      age = date.year - dob.year
      if date.month < dob.month || (date.month == dob.month && date.day < dob.day)
        age - 1
      else
        age
      end
    end

    # @!attribute relationship
    # @return [String] The relationship of the applicant to the primary applicant
    def relationship
      return @relationship if defined?(@relationship)

      primary_applicant = application.primary_applicant
      return nil unless primary_applicant

      @relationship = application.relationships.where(
        relative_id: primary_applicant.id,
        source_id: id
      )&.first&.kind
    end

    # Returns the first mailing address of the applicant.
    #
    # @return [Address, nil] the first mailing address if one exists, otherwise nil
    def mailing_address
      addresses.mailing.first
    end

    # Returns the first home address of the applicant.
    #
    # @return [Address, nil] the first home address if one exists, otherwise nil
    def home_address
      addresses.home.first
    end

    def is_state_resident?
      return true if is_homeless?

      address_to_use = addresses.collect(&:kind).include?('home') ? 'home' : 'mailing'
      addresses.each{|address| return true if address.kind == address_to_use && address.state == aca_state_abbreviation}
      false
    end

    # Defines the specific policy class for the applicant model
    def policy_class
      ApplicantPolicy
    end

    # Visitor pattern method to accept a visitor
    #
    # @param visitor [Eligibilities::Visitors::Visitor] The visitor to accept
    def accept(visitor)
      visitor.visit(self)
    end

    private

    # Adds to errors collection if duplicate eligibilities are found
    # @return [void]
    def unique_eligibilities
      eligibility_types = eligibilities.pluck(:_type)
      errors.add(:eligibilities, 'cannot have duplicate eligibilities types') if eligibility_types.uniq.length != eligibility_types.length
    end
  end
end
