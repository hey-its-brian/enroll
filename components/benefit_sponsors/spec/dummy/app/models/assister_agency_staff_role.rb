# frozen_string_literal: true

# A model for grouping and organizing AssisterAgencyStaffRole
class AssisterAgencyStaffRole
  include Mongoid::Document
  include SetCurrentUser
  include MongoidSupport::AssociationProxies
  include AASM

  embedded_in :person
  field :aasm_state, type: String, default: "assister_agency_pending"
  field :reason, type: String
  field :assister_agency_profile_id, type: BSON::ObjectId
  field :benefit_sponsors_assister_agency_profile_id, type: BSON::ObjectId
  embeds_many :workflow_state_transitions, as: :transitional
  # associated_with_one :assister_agency_profile, :assister_agency_profile_id, "AssisterAgencyProfile"  depricated


  associated_with_one :assister_agency_profile, :benefit_sponsors_assister_agency_profile_id, "BenefitSponsors::Organizations::AssisterAgencyProfile"

  validates_presence_of :benefit_sponsors_assister_agency_profile_id, :if => proc { |m| m.assister_agency_profile_id.blank? }
  validates_presence_of :assister_agency_profile_id, :if => proc { |m| m.benefit_sponsors_assister_agency_profile_id.blank? }

  accepts_nested_attributes_for :person, :workflow_state_transitions

  aasm do
    state :assister_agency_pending, initial: true
    state :active
    state :assister_agency_declined
    state :assister_agency_terminated

    event :assister_agency_accept, :after => [:record_transition, :send_invitation] do
      transitions from: :assister_agency_pending, to: :active
    end

    event :assister_agency_decline, :after => :record_transition do
      transitions from: :assister_agency_pending, to: :assister_agency_declined
    end

    event :assister_agency_terminate, :after => :record_transition do
      transitions from: :active, to: :assister_agency_terminated
      transitions from: :assister_agency_pending, to: :assister_agency_terminated
    end

    event :assister_agency_active, :after => :record_transition do
      transitions from: :assister_agency_terminated, to: :active
    end

    event :assister_agency_pending, :after => :record_transition do
      transitions from: :assister_agency_terminated, to: :assister_agency_pending
    end
  end

  # Scopes

  # @!scope class
  # @scope active
  # Retrieves all Assister Agency Staff Roles that are in the 'active' state.
  #
  # @return [Mongoid::Criteria<AssisterAgencyStaffRole>] Returns a Mongoid::Criteria of AssisterAgencyStaffRole objects that are in the 'active' state.
  #
  # @example Retrieve all active Assister Agency Staff Roles
  #   AssisterAgencyStaffRole.active #=> Mongoid::Criteria<AssisterAgencyStaffRole>
  scope :active, -> { where(aasm_state: 'active') }

  # @!scope class
  # @scope assister_agency_pending
  # Retrieves all Assister Agency Staff Roles that are in the 'assister_agency_pending' state.
  #
  # @return [Mongoid::Criteria<AssisterAgencyStaffRole>] Returns a Mongoid::Criteria of AssisterAgencyStaffRole objects that are in the 'assister_agency_pending' state.
  #
  # @example Retrieve all pending Assister Agency Staff Roles
  #   AssisterAgencyStaffRole.assister_agency_pending #=> Mongoid::Criteria<AssisterAgencyStaffRole>
  scope :assister_agency_pending, -> { where(aasm_state: 'assister_agency_pending') }

  # @!scope class
  # @scope by_profile_id
  # Retrieves all Assister Agency Staff Roles associated with a given Assister Agency Profile BSON::ObjectId.
  #
  # @param [BSON::ObjectId] profile_id The ID of the Assister Agency Profile for which to retrieve the Assister Agency Staff Roles.
  #
  # @return [Mongoid::Criteria<AssisterAgencyStaffRole>] Returns an Mongoid::Criteria of AssisterAgencyStaffRole objects associated with the given Assister Agency Profile BSON::ObjectId.
  #
  # @example Retrieve all Assister Agency Staff Roles for a given Assister Agency Profile BSON::ObjectId
  #   AssisterAgencyStaffRole.by_profile_id(profile_id) #=> Mongoid::Criteria<AssisterAgencyStaffRole>
  scope :by_profile_id, ->(profile_id) { where(benefit_sponsors_assister_agency_profile_id: profile_id) }

  def send_invitation
    # TODO: assister agency staff is not actively supported right now
    # Also this method call sends an employee invitation, which is bug 8028
    Invitation.invite_assister_agency_staff!(self)
  end

  def approve
    assister_agency_accept!
  end

  def current_state
    aasm_state.humanize.titleize
  end

  def email
    parent.emails.detect { |email| email.kind == "work" }
  end

  def email_address
    return nil unless email.present?
    email.address
  end

  def parent
    # raise "undefined parent: Person" unless self.person?
    person
  end

  def agency_pending?
    aasm_state == "assister_agency_pending"
  end

  def is_open?
    agency_pending? || is_active?
  end

  def is_active?
    aasm_state == "active"
  end

  ## Class methods
  class << self

    def find(id)
      return nil if id.blank?
      people = Person.where("assister_agency_staff_roles._id" => BSON::ObjectId.from_string(id))
      people.any? ? people[0].assister_agency_staff_roles.detect{|x| x.id.to_s == id.to_s} : nil
    end
  end

  private

  def latest_transition_time
    return unless workflow_state_transitions.any?

    workflow_state_transitions.first.transition_at
  end

  def record_transition
    workflow_state_transitions << WorkflowStateTransition.new(from_state: aasm.from_state,
                                                              to_state: aasm.to_state,
                                                              event: aasm.current_event)
  end
end
