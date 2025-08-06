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
    include ::L10nHelper

  # contact preference mapping
    CONTACT_METHOD_MAPPING = {
      ["Email", "Mail", "Text"] => "Paper, Electronic and Text Message communications",
      ["Email", "Text"] => "Electronic and Text Message communications",
      ["Email", "Mail"] => "Paper and Electronic communications",
      ["Mail", "Text"] => "Paper and Text Message communications",
      ["Text"] => "Only Text Message communication",
      ["Mail"] => "Only Paper communication",
      ["Email"] => "Only Electronic communications"
    }.freeze

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

    # @!attribute phones
    #   @return [Array<Locations::Phone>] Collection of phones associated with this applicant
    embeds_many :phones, class_name: 'Locations::Phone', as: :phoneable, cascade_callbacks: true, validate: true

    # @!attribute emails
    #   @return [Array<Locations::Email>] Collection of emails associated with this applicant
    embeds_many :emails, class_name: 'Locations::Email', as: :emailable, cascade_callbacks: true, validate: true

    before_create :assign_hbx_id

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

    # @!attribute is_temporarily_out_of_state
    #   @return [Boolean] Indicates if this applicant is temporarily out of state
    field :is_temporarily_out_of_state, type: Boolean

    # @!attribute age_off_excluded
    # @return [Boolean] Indicates if this applicant is should be kept on their parent's plan when they are 26+
    field :age_off_excluded, type: Boolean

    field :contact_method, type: String,
                           default: if EnrollRegistry.feature_enabled?(:contact_method_via_dropdown) || EnrollRegistry.feature_enabled?(:enroll_sms_notifications)
                                      "Paper and Electronic communications"
                                    else
                                      "Paper, Electronic and Text Message communications"
                                    end

    field :language_preference, type: String, default: "English"

    # @!attribute hbx_id
    # @return [String] The HBX ID for the applicant
    field :hbx_id, type: String

    validate :unique_eligibilities

    accepts_nested_attributes_for :person_name, :demographics, :eligibilities, :immigration_information, :addresses, :phones, :emails

    accepts_nested_attributes_for :phones, :reject_if => proc { |addy| addy[:full_phone_number].blank? }, allow_destroy: true
    accepts_nested_attributes_for :emails, :reject_if => proc { |addy| addy[:address].blank? }, allow_destroy: true

    # Finds and returns the family member associated with this applicant
    #
    # @return [FamilyMember] The family member associated with this applicant
    def family_member
      return @family_member if defined?(@family_member)

      @family_member = FamilyMember.find(family_member_id)
    end

    # Returns the person associated with this applicant
    #
    # @return [Person, nil] The person associated with the family member, or nil if no family member exists
    def person
      return @person if defined?(@person)

      @person = family_member.present? ? family_member.person : nil
    end

    # Returns the APTC/CSR eligibility for the applicant.
    def aptc_csr_eligibility
      eligibilities.where(_type: 'Eligibilities::V3::AptcCsrEligibility').first
    end

    # Returns the Individual Market eligibility for the applicant.
    def individual_market_eligibility
      eligibilities.where(_type: 'Eligibilities::V3::IndividualMarketEligibility').first
    end

    def find_person
      match_criteria, records = ::Operations::People::Match.new.call({:dob => demographics.dob,
                                                                      :last_name => person_name.family_name,
                                                                      :first_name => person_name.given_name,
                                                                      :ssn => demographics.encrypted_ssn})
      return unless records.present?
      return unless [:ssn_present, :dob_present].include?(match_criteria)
      return if match_criteria == :dob_present && demographics.encrypted_ssn.present? && records.first.ssn != demographics.encrypted_ssn

      records.first
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

    def home_phone
      phones.detect { |phone| phone.kind == "home" }
    end

    def mobile_phone
      phones.detect { |phone| phone.kind == "mobile" }
    end

    def home_email
      emails.detect { |adr| adr.kind == "home" }
    end

    def work_email
      emails.detect { |adr| adr.kind == "work" }
    end

    # Returns the first work address of the applicant.
    #
    # @return [Address, nil] the first work address if one exists, otherwise nil
    def work_address
      addresses.work.first
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

    # Method to build Individual Market Eligibility and evidences for the applicant.
    #   It creates Individual Market Eligibility if it does not exist.
    #   It calls the method to build evidences for Individual Market Eligibility if they do not exist.
    #
    # @return [void]
    def build_ivl_eligibility_with_evidences
      build_individual_market_eligibility unless individual_market_eligibility
      build_individual_market_evidences
    end

    # Builds a new Individual Market Eligibility for this applicant
    #
    # @return [Eligibilities::V3::IndividualMarketEligibility] The new Individual Market Eligibility
    def build_individual_market_eligibility
      return if individual_market_eligibility.present?
      eligibilities.build(
        _type: "Eligibilities::V3::IndividualMarketEligibility",
        title: 'Individual Market Eligibility',
        key: :individual_market_eligibility
      )
    end

    # Builds a new APTC/CSR Eligibility for this applicant
    #
    # @return [Eligibilities::V3::AptcCsrEligibility] The new APTC/CSR Eligibility
    def build_aptc_csr_eligibility
      return if aptc_csr_eligibility.present?

      eligibilities.build(
        _type: 'Eligibilities::V3::AptcCsrEligibility',
        title: 'APTC/CSR Eligibility',
        key: :aptc_csr_eligibility
      )
    end

    def program_eligibility
      return l10n("applications.program.did_not_apply") unless is_applying_coverage
      individual_market_eligibility&.qhp_determination&.is_eligible == true ? l10n("applications.program.qhp_plan", short_name: EnrollRegistry[:enroll_app].setting(:short_name).item) : l10n("applications.program.not_eligible")
    end

    # Creates a copy of this applicant in a new application
    #
    # @param [IndividualMarket::Application] new_application The application where the copied applicant will be created
    # @return [IndividualMarket::Applicant] The newly created applicant with copied attributes and embedded documents
    # @example Copy an applicant to a new application
    #   original_applicant.copy_applicant(new_application)
    def copy_applicant(new_application)
      new_applicant = new_application.applicants.build(
        family_member_id: family_member_id,
        is_primary_applicant: is_primary_applicant,
        address_same_as_primary: address_same_as_primary,
        is_applying_coverage: is_applying_coverage,
        is_homeless: is_homeless,
        age_off_excluded: age_off_excluded,
        contact_method: contact_method,
        language_preference: language_preference
      )

      person_name.copy_person_name(new_applicant) if person_name.present?
      demographics.copy_demographics(new_applicant) if demographics.present?
      immigration_information.copy_immigration_information(new_applicant) if immigration_information.present?

      new_applicant.build_individual_market_eligibility

      addresses.each do |address|
        address.copy_address(new_applicant)
      end

      phones.each do |phone|
        phone.copy_phone(new_applicant)
      end

      emails.each do |email|
        email.copy_email(new_applicant)
      end

      new_applicant
    end

    # this attribute is used to identify the applicant in the application
    # so it works with the qhp application javascript controller to properly identify the applicant
    # to open the correct applicant edit form.
    # @!attribute reference_id
    #   @return [String] The reference ID for the applicant
    def reference_id
      family_member_id || id
    end

    def build_individual_market_evidences
      return unless individual_market_eligibility.present?
      build_citizenship_evidence
      build_immigration_evidence
      build_american_indian_evidence
      build_social_security_number_evidence

      # We do not have residency evidence verification for any client we are currently supporting from this codebase
      # build_residency_evidence

      # Previously, the AliveStatus VerificationType was added on a person
      # during a person.save event, we are creating it here as well to mimic that logic
      build_alive_evidence
    end

    # Builds citizenship evidence if the applicant is applying for coverage, does not have citizenship evidence, and consumer is a US citizen or naturalized citizen.
    #   It creates a citizenship evidence and moves it to pending state.
    #
    # @return [void]
    def build_citizenship_evidence
      return individual_market_eligibility.citizenship_evidence if individual_market_eligibility.citizenship_evidence
      return unless is_applying_coverage
      return if [ConsumerRole::US_CITIZEN_STATUS, ConsumerRole::NATURALIZED_CITIZEN_STATUS].exclude?(demographics.citizen_status)

      evidence = individual_market_eligibility.evidences.build(
        _type: 'Eligibilities::V3::Evidences::CitizenshipEvidence',
        title: 'Citizenship Evidence',
        key: :citizenship_evidence
      )
      evidence.move_to_pending(
        comment: 'application_determination',
        reason: 'Citizenship evidence is required for QHP eligibility'
      )
      evidence
    end

    # Builds immigration evidence if the applicant is applying for coverage, does not have immigration evidence, and consumer is alien lawfully present.
    #   It creates an immigration evidence and moves it to pending state.
    #
    # @return [void]
    def build_immigration_evidence
      return individual_market_eligibility.immigration_evidence if individual_market_eligibility.immigration_evidence
      return unless is_applying_coverage
      return if ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS != demographics.citizen_status

      evidence = individual_market_eligibility.evidences.build(
        _type: 'Eligibilities::V3::Evidences::ImmigrationEvidence',
        title: 'Immigration Evidence',
        key: :immigration_evidence
      )

      evidence.move_to_pending(
        comment: 'application_determination',
        reason: 'Immigration evidence is required for QHP eligibility'
      )
      evidence
    end

    # Builds American Indian evidence if the applicant is an Indian tribe member and does not have American Indian evidence.
    #   It creates an American Indian evidence and moves it to attested or pending state based on the feature flag.
    #
    # @return [void]
    def build_american_indian_evidence
      return individual_market_eligibility.american_indian_evidence if individual_market_eligibility.american_indian_evidence
      return unless demographics.indian_tribe_member

      evidence = individual_market_eligibility.evidences.build(
        _type: 'Eligibilities::V3::Evidences::AmericanIndianEvidence',
        title: 'American Indian Evidence',
        key: :american_indian_evidence
      )

      if EnrollRegistry.feature_enabled?(:ai_an_self_attestation)
        evidence.move_to_attested(
          comment: 'application_determination',
          reason: 'American Indian evidence is required for QHP eligibility'
        )
      else
        evidence.move_to_pending(
          comment: 'application_determination',
          reason: 'American Indian evidence is required for QHP eligibility'
        )
      end
      evidence
    end

    # Builds social security number evidence if the applicant does not have it and has an encrypted SSN.
    # It creates a social security number evidence and moves it to pending state.
    #
    # @return [void]
    def build_social_security_number_evidence
      return individual_market_eligibility.social_security_number_evidence if individual_market_eligibility.social_security_number_evidence
      return if demographics.encrypted_ssn.blank?

      evidence = individual_market_eligibility.evidences.build(
        _type: 'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence',
        title: 'Social Security Number Evidence',
        key: :social_security_number_evidence
      )

      evidence.move_to_pending(
        comment: 'application_determination',
        reason: 'Social Security Number evidence is required for QHP eligibility'
      )
      evidence
    end

    # Builds alive evidence if the applicant does not have it and has an encrypted SSN.
    # It creates an alive evidence and moves it to pending state.
    #
    # @return [void]
    def build_alive_evidence
      return individual_market_eligibility.alive_evidence if individual_market_eligibility&.alive_evidence
      return if demographics.encrypted_ssn.blank?
      return unless is_applying_coverage

      evidence = individual_market_eligibility.evidences.build(
        _type: 'Eligibilities::V3::Evidences::AliveEvidence',
        title: 'Alive Evidence',
        key: :alive_evidence
      )

      evidence.move_to_unverified(
        comment: 'application_determination',
        reason: 'Alive evidence can only be moved to :outstanding or :attested by the DMF call'
      )
      evidence
    end

    # Finds if the applicant is eligible for QHP based on the individual market eligibility and qhp determination.
    #
    # @return [Boolean] true if the applicant is eligible for QHP, false otherwise
    def is_qhp_eligible
      individual_market_eligibility.qhp_determination&.is_eligible
    end

    # Finds if the applicant is eligible for CSR based on the individual market eligibility and csr determination.
    #
    # @return [Boolean] true if the applicant is eligible for CSR, false otherwise
    def is_csr_eligible
      individual_market_eligibility.csr_determination&.is_eligible
    end

    # Returns the CSR type for the applicant based on the individual market eligibility.
    #
    # @return [String] The CSR type, defaults to 'csr_0' if not determined
    # @see Eligibilities::V3::Determinations::CsrDetermination#CSR_TYPE_KINDS for valid values
    def csr_type
      individual_market_eligibility.csr_determination&.csr_type || 'csr_0'
    end

    # Returns the CSR percentage for the applicant based on the CSR type.
    #
    # @return [Integer] The CSR percentage, returns 0 for 'csr_0', -1 for 'csr_limited', and the corresponding percentage for other types
    def csr_percent
      {
        'csr_100' => 100,
        'csr_94' => 94,
        'csr_87' => 87,
        'csr_73' => 73,
        'csr_limited' => -1,
        'csr_0' => 0
      }[csr_type]
    end

    # Retains evidence information from another applicant for the individual market eligibility.
    #
    # @param applicant [IndividualMarket::Applicant, FinancialAssistance::Applicant] The applicant to retain evidence information from
    #
    # @return [void]
    def retain_evidence_information(applicant)
      individual_market_eligibility.retain_evidence_information(applicant.individual_market_eligibility)
    end

    private

    # Adds to errors collection if duplicate eligibilities are found
    # @return [void]
    def unique_eligibilities
      eligibility_types = eligibilities.pluck(:_type)
      errors.add(:eligibilities, 'cannot have duplicate eligibilities types') if eligibility_types.uniq.length != eligibility_types.length
    end

    def assign_hbx_id
      self.hbx_id ||= ::HbxIdGenerator.generate_application_id
    end
  end
end
