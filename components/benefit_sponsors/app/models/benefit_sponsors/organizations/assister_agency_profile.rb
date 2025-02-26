# frozen_string_literal: true

module BenefitSponsors
  module Organizations
    # model for assister agency profile
    class AssisterAgencyProfile < BenefitSponsors::Organizations::Profile
      include ::SetCurrentUser
      include AASM
      include ::Config::AcaModelConcern
      include ::Config::SiteModelConcern
      include Acapi::Notifiers
      include ::BenefitSponsors::Concerns::Observable
      include ::BenefitSponsors::ModelEvents::AssisterAgencyProfile

      MARKET_KINDS = [].tap do |a|
        a << :individual if is_individual_market_enabled?
        a << :shop if is_shop_or_fehb_market_enabled?
        a << :both if is_shop_or_fehb_market_enabled?
      end

      # @!attribute INDIVIDUAL_MARKET_KINDS
      #   @return [Array<Symbol>] Represents the market types that are considered as individual markets.
      #   The possible values are :both and :individual.
      INDIVIDUAL_MARKET_KINDS = %i[both individual].freeze

      # @!attribute SHOP_MARKET_KINDS
      #   @return [Array<Symbol>] Represents the market types that are considered as shop markets.
      #   The possible values are :both and :shop.
      SHOP_MARKET_KINDS = %i[both shop].freeze

      ALL_MARKET_KINDS_OPTIONS = {}.tap do |h|
        h["Individual & Family Marketplace ONLY"] = "individual" if is_individual_market_enabled?
        h["Small Business Marketplace ONLY"] = "shop" if is_shop_or_fehb_market_enabled?
        h["Both - Individual & Family AND Small Business Marketplaces"] = "both" if is_shop_or_fehb_market_enabled?
      end

      MARKET_KINDS_OPTIONS = ALL_MARKET_KINDS_OPTIONS.select { |_k,v| MARKET_KINDS.include? v.to_sym }

      field :market_kind, type: Symbol
      field :corporate_aoid, type: String
      field :primary_assister_role_id, type: BSON::ObjectId
      field :default_general_agency_profile_id, type: BSON::ObjectId

      field :languages_spoken, type: Array, default: ["en"] # TODO
      field :working_hours, type: Boolean
      field :accept_new_clients, type: Boolean

      field :ach_routing_number, type: String
      field :ach_account_number, type: String

      field :aasm_state, type: String

      field :home_page, type: String

      # embeds_many :documents, as: :documentable
      accepts_nested_attributes_for :inbox

      has_many :assister_agency_contacts, class_name: "Person", inverse_of: :assister_agency_contact
      accepts_nested_attributes_for :assister_agency_contacts, reject_if: :all_blank, allow_destroy: true

      validates_presence_of :market_kind

      validates :corporate_aoid,
                numericality: {only_integer: true},
                length: { minimum: 1, maximum: 10 },
                uniqueness: true,
                allow_blank: true

      validates_presence_of :languages_spoken

      # validates :market_kind,
      #   inclusion: { in: BenefitSponsors::Organizations::AssisterAgencyProfile::MARKET_KINDS, message: "%{value} is not a valid practice area" },
      #   allow_blank: false

      before_save :notify_before_save

      validate :validate_market_kind
      validate :validate_at_least_one_language_selected
      # add_observer ::BenefitSponsors::Observers::NoticeObserver.new, [:process_assister_agency_profile_events]

      after_initialize :build_nested_models

      scope :active,      ->{ any_in(aasm_state: ["is_applicant", "is_approved"]) }
      scope :inactive,    ->{ any_in(aasm_state: ["is_rejected", "is_suspended", "is_closed"]) }

      # has_one primary_assister_role
      def primary_assister_role=(new_primary_assister_role = nil)
        if new_primary_assister_role.present?
          raise ArgumentError, "expected AssisterRole class" unless new_primary_assister_role.is_a? AssisterRole
          self.primary_assister_role_id = new_primary_assister_role._id
        else
          unset("primary_assister_role_id")
        end
        @primary_assister_role = new_primary_assister_role
      end

      def validate_market_kind
        errors.add(:profiles, "#{market_kind} is not a valid practice area") unless BenefitSponsors::Organizations::AssisterAgencyProfile::MARKET_KINDS.include?(market_kind)
      end

      def validate_at_least_one_language_selected
        return if self&.languages_spoken&.any?

        errors.add(:languages_spoken, "At least one language must be selected.")
      end

      def primary_assister_role
        return @primary_assister_role if defined? @primary_assister_role
        @primary_assister_role = AssisterRole.find(self.primary_assister_role_id) unless primary_assister_role_id.blank?
      end

      def active_assister_roles
        @active_assister_roles = AssisterRole.find_active_by_assister_agency_profile(self)
      end

      def employer_clients
        # return unless (MARKET_KINDS - ["individual"]).include?(market_kind)
        return @employer_clients if defined? @employer_clients
        @employer_clients = BenefitSponsors::Concerns::EmployerProfileConcern.find_by_assister_agency_profile(self)
      end

      def family_clients; end

      def market_kinds
        MARKET_KINDS_OPTIONS
      end

      def language_options
        LanguageList::COMMON_LANGUAGES
      end

      def languages
        return unless languages_spoken.any?
        languages_spoken.map {|lan| LanguageList::LanguageInfo.find(lan).name if LanguageList::LanguageInfo.find(lan)}.compact.join(",")
      end

      def primary_office_location
        office_locations.detect(&:is_primary?)
      end

      def commission_statements
        documents.where(subject: "commission-statement")
      end

      def phone
        office = primary_office_location
        office && office.phone.to_s
      end

      def primary_aoid
        @primary_assister_role.assister_org_id
      end

      def linked_employees
        employer_profiles = BenefitSponsors::Concerns::EmployerProfileConcern.find_by_assister_agency_profile(self)
        return unless employer_profiles

        emp_ids = employer_profiles.map(&:id)
        Person.where(:'employee_roles.benefit_sponsors_employer_profile_id'.in => emp_ids)
      end

      def families
        linked_active_employees = linked_employees.select(&:has_active_employee_role?)
        employee_families = linked_active_employees.map(&:primary_family).to_a
        consumer_families = Family.by_assister_agency_profile_id(self.id).to_a
        families = (consumer_families + employee_families).uniq
        families.sort_by{|f| f.primary_applicant.person.last_name}
      end

      def default_general_agency_profile=(new_default_general_agency_profile = nil)
        if new_default_general_agency_profile.present?
          raise ArgumentError, "expected GeneralAgencyProfile class" unless new_default_general_agency_profile.is_a? BenefitSponsors::Organizations::GeneralAgencyProfile
          self.default_general_agency_profile_id = new_default_general_agency_profile.id
        else
          self.default_general_agency_profile_id = nil
        end
        @default_general_agency_profile = new_default_general_agency_profile
      end

      def default_general_agency_profile
        return @default_general_agency_profile if defined? @default_general_agency_profile
        @default_general_agency_profile = BenefitSponsors::Organizations::GeneralAgencyProfile.find(self.default_general_agency_profile_id) if default_general_agency_profile_id.present?
      end

      aasm do #no_direct_assignment: true do
        state :is_applicant, initial: true
        state :is_approved
        state :is_rejected
        state :is_suspended
        state :is_closed

        event :approve do
          transitions from: [:is_applicant, :is_suspended], to: :is_approved
        end

        event :reject do
          transitions from: :is_applicant, to: :is_rejected
        end

        event :suspend do
          transitions from: [:is_applicant, :is_approved], to: :is_suspended
        end

        event :close do
          transitions from: [:is_approved, :is_suspended], to: :is_closed
        end
      end

      # Checks if the assister agency profile is associated with the individual market.
      # It checks if the market_kind of the assister agency profile is included in the INDIVIDUAL_MARKET_KINDS.
      #
      # @return [Boolean] Returns true if the assister agency profile is associated with the individual market, false otherwise.
      def individual_market?
        INDIVIDUAL_MARKET_KINDS.include?(market_kind)
      end

      # Checks if the assister agency profile is associated with the shop market.
      # It checks if the market_kind of the assister agency profile is included in the SHOP_MARKET_KINDS.
      #
      # @return [Boolean] Returns true if the assister agency profile is associated with the shop market, false otherwise.
      def shop_market?
        SHOP_MARKET_KINDS.include?(market_kind)
      end

      private

      def initialize_profile
        return unless is_benefit_sponsorship_eligible.blank?

        write_attribute(:is_benefit_sponsorship_eligible, false)
        @is_benefit_sponsorship_eligible = false
        self
      end

      def build_nested_models
        build_inbox if inbox.nil?
      end

    end
  end
end
