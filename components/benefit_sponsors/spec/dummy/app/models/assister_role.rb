# frozen_string_literal: true

# A model for grouping and organizing AssisterRole
class AssisterRole
  include Mongoid::Document
  include SetCurrentUser
  include Mongoid::Timestamps
  include AASM

  PROVIDER_KINDS = %w[assister assister].freeze
  ASSISTER_UPDATED_EVENT_NAME = "acapi.info.events.assister.updated"

  ASSISTER_ROLE_STATUS_TYPES = ['applicant', 'certified', 'pending', 'decertified', 'denied', 'extended', 'imported','all'].freeze

  embedded_in :person

  field :aasm_state, type: String

  # assister organization ID (unique identifier)
  field :assister_org_id, type: String
  field :assister_agency_profile_id, type: BSON::ObjectId
  field :benefit_sponsors_assister_agency_profile_id, type: BSON::ObjectId
  field :provider_kind, type: String
  field :reason, type: String

  # @!attribute market_kind
  #   @return [String] Represents the market type that the assister is associated with.
  #   This field is not being used consistently across the application and may yield unexpected results.
  #   It is recommended to fetch or depend on this field only after we start to persist information consistently.
  field :market_kind, type: String

  field :languages_spoken, type: Array, default: ["en"]
  field :working_hours, type: Boolean, default: false
  field :accept_new_clients, type: Boolean
  field :license, type: Boolean
  field :training, type: Boolean
  field :carrier_appointments, type: Hash, default: EnrollRegistry[:brokers].setting(:carrier_appointments).item || {}

  embeds_many :workflow_state_transitions, as: :transitional

  delegate :hbx_id, :hbx_id=, to: :person, allow_nil: true

  field :organization, type: String
  field :assister_org_id, type: String
  accepts_nested_attributes_for :person, :workflow_state_transitions

  after_initialize :initial_transition

  validates_presence_of :assister_org_id, :provider_kind
  validates_uniqueness_of :assister_org_id
  validates_length_of :assister_org_id, :in => 1..10, :allow_blank => false
  validate :assister_org_id_format


  validates :provider_kind,
            allow_blank: false,
            inclusion: { in: PROVIDER_KINDS, message: "%{value} is not a valid provider kind" }

  scope :active,    ->{ any_in(aasm_state: ["applicant", "active", "assister_agency_pending"]) }
  scope :inactive,  ->{ any_in(aasm_state: ["denied", "decertified", "assister_agency_declined", "assister_agency_terminated"]) }

  def self.by_assister_org_id(assister_org_id)
    person_records = Person.by_assister_role_assister_org_id(assister_org_id)
    return [] unless person_records.any?
    person_records.select do |pr|
      pr.assister_role.present? &&
        (pr.assister_role.assister_org_id == assister_org_id)
    end.map(&:assister_role)
  end

  # Checks if the assister is associated with the individual market.
  # As the field market_kind is not being used properly, we depend on Assister Agency Profile's market_kind.
  #
  # @return [Boolean] Returns true if the assister is associated with the individual market, false otherwise.
  def individual_market?
    return false unless assister_agency_profile

    assister_agency_profile.individual_market?
  end

  # Checks if the assister is associated with the shop market.
  # As the field market_kind is not being used properly, we depend on Assister Agency Profile's market_kind.
  #
  # @return [Boolean] Returns true if the assister is associated with the shop market, false otherwise.
  def shop_market?
    return false unless assister_agency_profile

    assister_agency_profile.shop_market?
  end

  def email_address
    return nil unless email.present?
    email.address
  end

  def parent
    # raise "undefined parent: Person" unless self.person?
    self.person
  end

  # belongs_to assister_agency_profile
  def assister_agency_profile=(new_assister_agency)
    if new_assister_agency.is_a? BenefitSponsors::Organizations::AssisterAgencyProfile
      if new_assister_agency.nil?
        self.benefit_sponsors_assister_agency_profile_id = nil
      else
        raise ArgumentError, "expected BenefitSponsors::Organizations::AssisterAgencyProfile class" unless new_assister_agency.is_a? BenefitSponsors::Organizations::AssisterAgencyProfile
        self.benefit_sponsors_assister_agency_profile_id = new_assister_agency._id
        @assister_agency_profile = new_assister_agency
      end
    elsif new_assister_agency.nil?
      self.assister_agency_profile_id = nil
    else
      raise ArgumentError, "expected AssisterAgencyProfile class" unless new_assister_agency.is_a? AssisterAgencyProfile
      self.assister_agency_profile_id = new_assister_agency._id
      @assister_agency_profile = new_assister_agency
    end
  end

  def assister_agency_profile
    return @assister_agency_profile if defined? @assister_agency_profile
    if self.benefit_sponsors_assister_agency_profile_id.nil?
      @assister_agency_profile = AssisterAgencyProfile.find(assister_agency_profile_id) if has_assister_agency_profile?
    elsif has_assister_agency_profile?
      @assister_agency_profile = BenefitSponsors::Organizations::Organization.where(:"profiles._id" => benefit_sponsors_assister_agency_profile_id).first.assister_agency_profile
    end
  end

  def has_assister_agency_profile?
    self.benefit_sponsors_assister_agency_profile_id.present? || self.assister_agency_profile_id.present?
  end

  def can_update_carrier_appointments?
    active?
  end

  def address=(new_address)
    parent.addresses << new_address
  end

  def address
    parent.addresses.detect { |addr| addr.kind == "work" }
  end

  def phone=(new_phone)
    parent.phones << new_phone
  end

  def phone
    parent.phones.where(kind: "work").first || parent.phones.where(kind: "main").first || assister_agency_profile.phone
  rescue StandardError => _e
    ""
  end

  def email=(new_email)
    parent.emails << new_email
  end

  def email
    parent.emails.detect { |email| email.kind == "work" }
  end

  def send_invitation
    return unless active?
    Invitation.invite_assister!(self)
  end

  ## Class methods
  class << self

    def find(id)
      return nil if id.blank?
      people = Person.where("assister_role._id" => BSON::ObjectId.from_string(id))
      people.any? ? people[0].assister_role : nil
    end

    def find_by_assister_org_id(assister_org_id_value)
      person = Person.where("assister_role.assister_org_id" => assister_org_id_value)
      person.first.assister_role unless person.blank?
    end

    def list_assisters(person_list)
      person_list.reduce([]) { |assisters, person| assisters << person.assister_role }
    end

    # TODO; return as chainable Mongoid::Criteria
    def all
      # criteria = Mongoid::Criteria.new(Person)
      list_assisters(Person.exists(assister_role: true))
    end

    def first
      all.first
    end

    def last
      all.last
    end

    def find_by_assister_agency_profile(assister_agency_profile)
      raise ArgumentError, "expected AssisterAgencyProfile" unless assister_agency_profile.is_a?(BenefitSponsors::Organizations::AssisterAgencyProfile)
      people = Person.where("assister_role.benefit_sponsors_assister_agency_profile_id" => assister_agency_profile.id)
      people.collect(&:assister_role)
    end

    def find_candidates_by_assister_agency_profile(assister_agency_profile)
      people = Person.where(:"assister_role.benefit_sponsors_assister_agency_profile_id" => assister_agency_profile.id)\
                     .any_in(:"assister_role.aasm_state" => ["applicant", "assister_agency_pending"])
      people.collect(&:assister_role)
    end

    def find_active_by_assister_agency_profile(assister_agency_profile)
      people = Person.and(:"assister_role.benefit_sponsors_assister_agency_profile_id" => assister_agency_profile.id,
                          :"assister_role.aasm_state" => "active")
      people.collect(&:assister_role)
    end

    def find_inactive_by_assister_agency_profile(assister_agency_profile)
      people = Person.where(:"assister_role.benefit_sponsors_assister_agency_profile_id" => assister_agency_profile.id)\
                     .any_in(:"assister_role.aasm_state" => ["denied", "decertified", "assister_agency_declined", "assister_agency_terminated"])
      people.collect(&:assister_role)
    end

    def agency_ids_for_active_assisters
      Person.collection.raw_aggregate([
        {"$match" => {"assister_role.aasm_state" => "active"}},
        {"$group" => {"_id" => "$assister_role.benefit_sponsors_assister_agency_profile_id"}}
      ]).map do |record|
        record["_id"]
      end
    end

    def assisters_matching_search_criteria(search_str)
      Person.exists(assister_role: true).search_first_name_last_name_assister_org_id(search_str).where("assister_role.aasm_state" => "active")
    end

    def agencies_with_matching_assister(search_str)
      assister_role_ids = assisters_matching_search_criteria(search_str).map(&:assister_role).map(&:id)
      if assisters_matching_search_criteria(search_str).map(&:assister_role).detect(&:benefit_sponsors_assister_agency_profile_id).present?
        Person.collection.raw_aggregate([
                                            {"$match" => {"assister_role.aasm_state" => "active", "assister_role._id" => { "$in" => assister_role_ids}}},
                                            {"$group" => {"_id" => "$assister_role.benefit_sponsors_assister_agency_profile_id"}}
                                        ]).map do |record|
          record["_id"]
        end
      else
        Person.collection.raw_aggregate([
                                            {"$match" => {"assister_role.aasm_state" => "active", "assister_role._id" => { "$in" => assister_role_ids}}},
                                            {"$group" => {"_id" => "$assister_role.assister_agency_profile_id"}}
                                        ]).map do |record|
          record["_id"]
        end
      end
    end
  end

  aasm do
    state :applicant, initial: true
    state :active
    state :denied
    state :decertified
    state :assister_agency_pending
    state :assister_agency_declined
    state :assister_agency_terminated
    state :application_extended
    state :imported

    event :approve, :after => [:record_transition, :send_invitation, :notify_updated] do
      transitions from: [:applicant, :application_extended, :imported], to: :active, :guard => :is_primary_assister?
      transitions from: :assister_agency_pending, to: :active, :guard => :is_primary_assister?
      transitions from: :applicant, to: :assister_agency_pending
    end

    event :pending, :after => [:record_transition, :notify_updated, :notify_assister_pending] do
      transitions from: :applicant, to: :assister_agency_pending, :guard => :is_primary_assister?
      transitions from: :assister_agency_pending, to: :assister_agency_pending, :guard => :is_primary_assister?
    end

    event :assister_agency_accept, :after => [:record_transition, :send_invitation, :notify_updated] do
      transitions from: [:assister_agency_pending, :application_extended], to: :active
    end

    event :assister_agency_decline, :after => :record_transition do
      transitions from: [:assister_agency_pending, :application_extended], to: :assister_agency_declined
    end

    event :assister_agency_terminate, :after => [:record_transition, :remove_assister_assignments] do
      transitions from: :active, to: :assister_agency_terminated
    end

    event :deny, :after => [:record_transition, :notify_assister_denial]  do
      transitions from: [:applicant, :assister_agency_pending, :application_extended], to: :denied
    end

    event :decertify, :after => [:record_transition, :remove_assister_assignments]  do
      transitions from: :active, to: :decertified
    end

    # Attempt to achieve or return to good standing with HBX
    event :reapply, :after => :record_transition  do
      transitions from: [:applicant, :decertified, :denied, :assister_agency_declined], to: :applicant
    end

    # Moves between assister agency organizations that don't require HBX re-certification
    event :transfer, :after => :record_transition  do
      transitions from: [:active, :assister_agency_pending, :assister_agency_terminated], to: :applicant
    end

    # Not currently supported in UI.   Datafix only person.assister_role.recertify! refs #12398
    event :recertify, :after => :record_transition do
      transitions from: :decertified, to: :active
    end

    # Extends the assister application denial time
    event :extend_application, :after => :record_transition do
      transitions from: :application_extended, to: :application_extended, :after => :notify_assister_pending
      transitions from: [:assister_agency_pending, :denied], to: :application_extended
    end

    # Imported assisters will be placed in imported state
    event :import, :after => :record_transition do
      transitions from: :applicant, to: :imported
    end
  end

  def notify_updated
    notify(ASSISTER_UPDATED_EVENT_NAME, { :assister_id => self.assister_org_id })
  end

  def active?
    aasm_state == 'active'
  end

  # @method create_basr_for_person_with_consumer_role
  # Creates a Assister Agency Staff Role (BASR) for a person with a consumer role.
  #
  # This method checks:
  #   - if the 'assister_role_consumer_enhancement' feature is enabled
  #   - if the person has a consumer role
  #   - if the person has a user
  #   - if the person already has a BASR for the current assister agency profile.
  #   If all these conditions are met, it creates a new BASR for the person with the current assister agency profile.
  #
  # @return [AssisterAgencyStaffRole, nil]
  #   Returns the newly created AssisterAgencyStaffRole if it was created, or nil if no role was created.
  #
  # @example Create a BASR for a person with a consumer role
  #   create_basr_for_person_with_consumer_role
  def create_basr_for_person_with_consumer_role
    return unless EnrollRegistry.feature_enabled?(:broker_role_consumer_enhancement)
    return if person.consumer_role.blank?
    return if person.user.blank?
    return if person.pending_basr_by_profile_id(benefit_sponsors_assister_agency_profile_id)

    person.create_assister_agency_staff_role(
      benefit_sponsors_assister_agency_profile_id: benefit_sponsors_assister_agency_profile_id
    )
  end

  private

  def assister_org_id_format
    return unless assister_org_id.present?
    valid_format = if EnrollRegistry.feature_enabled?(:allow_alphanumeric_npn)
                     ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a.map(&:to_s)
                   else
                     (0..9).to_a.map(&:to_s)
                   end
    assister_org_id_chars = assister_org_id.split("")
    invalid_assister_org_id_chars_present = assister_org_id_chars.any? { |ch| !ch.in?(valid_format) }
    return unless invalid_assister_org_id_chars_present
    errors.add(
      :assister_org_id,
      l10n("assister_agencies.profiles.assister_org_id_alphanumeric_error")
    )
  end

  def is_primary_assister?
    return false unless assister_agency_profile
    assister_agency_profile.primary_assister_role == self
  end

  def initial_transition
    return unless workflow_state_transitions.empty?

    self.workflow_state_transitions << WorkflowStateTransition.new(
      from_state: nil,
      to_state: aasm.to_state || "applicant"
    )
  end

  def record_transition
    self.workflow_state_transitions << WorkflowStateTransition.new(
      from_state: aasm.from_state,
      to_state: aasm.to_state,
      event: aasm.current_event
    )
  end

  def notify_assister_denial
    UserMailer.assister_denied_notification(self).deliver_now
  end

  def notify_assister_pending
    unchecked_carriers = self.carrier_appointments.select { |k,v| k if v != "true"}
    UserMailer.assister_pending_notification(self,unchecked_carriers).deliver_now if unchecked_carriers.present? || !self.training
  end

  def applicant?
    aasm_state == 'applicant'
  end

  def agency_pending?
    aasm_state == 'assister_agency_pending'
  end

  def approved_or_pending?
    aasm_state == 'active'
  end

  def latest_transition_time
    self.workflow_state_transitions.first.transition_at if self.workflow_state_transitions.any?
  end

  def current_state
    aasm_state.gsub(/_/,' ').camelcase
  end

  def remove_assister_assignments
    @orgs = BenefitSponsors::BenefitSponsorships::BenefitSponsorship.by_assister_role(id).map(&:organization)

    @employers = @orgs.map(&:employer_profile)
    # Remove assister from employers
    @employers.each do |e|
      e.fire_assister_agency
      # Remove General Agency
      e.fire_general_agency!(TimeKeeper.datetime_of_record)
    end
    # Remove assister from families
    return unless has_assister_agency_profile?

    families = self.assister_agency_profile.families
    families.each(&:terminate_assister_agency)
  end
end
