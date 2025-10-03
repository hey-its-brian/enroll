class FamilyMember
  include Mongoid::Document
  include SetCurrentUser
  include Mongoid::Timestamps
  include MongoidSupport::AssociationProxies
  include ApplicationHelper
  include GlobalID::Identification
  include EventSource::Command

  # includes TimeHelper module for time related helper methods
  include TimeHelper

  # includes ResourceRegistryHelper module to handle feature flags
  include ResourceRegistryHelper

  embedded_in :family

  # Responsible for updating eligibility when family member is created/updated
  after_create :family_member_created
  before_create :notify_family
  after_update :family_member_updated, if: :is_active_changed?
  after_destroy :notify_family

  # Person responsible for this family
  field :is_primary_applicant, type: Boolean, default: false

  # Person is applying for coverage
  field :is_coverage_applicant, type: Boolean, default: true

  # Person who authorizes auto-renewal eligibility check
  field :is_consent_applicant, type: Boolean, default: false

  field :is_active, type: Boolean, default: true

  field :person_id, type: BSON::ObjectId
  field :broker_role_id, type: BSON::ObjectId

  # Immediately preceding family where this person was a member
  field :former_family_id, type: BSON::ObjectId

  field :external_member_id, type: String

  validate :no_duplicate_family_members

  scope :active, ->{ where(is_active: true).where(:created_at.ne => nil) }
  scope :by_primary_member_role, ->{ where(:is_active => true).where(:is_primary_applicant => true) }
  embeds_many :hbx_enrollment_exemptions
  accepts_nested_attributes_for :hbx_enrollment_exemptions

  embeds_many :comments, cascade_callbacks: true
  accepts_nested_attributes_for :comments, reject_if: proc { |attribs| attribs['content'].blank? }, allow_destroy: true

  delegate :id, to: :family, prefix: true

  delegate :hbx_id, to: :person, allow_nil: true
  delegate :first_name, to: :person, allow_nil: true
  delegate :last_name, to: :person, allow_nil: true
  delegate :middle_name, to: :person, allow_nil: true
  delegate :full_name, to: :person, allow_nil: true
  delegate :name_pfx, to: :person, allow_nil: true
  delegate :name_sfx, to: :person, allow_nil: true
  delegate :date_of_birth, to: :person, allow_nil: true
  delegate :dob, to: :person, allow_nil: true
  delegate :ssn, to: :person, allow_nil: true
  delegate :no_ssn, to: :person, allow_nil: true
  delegate :gender, to: :person, allow_nil: true
  delegate :rating_address, to: :person, allow_nil: true
  # consumer fields
  delegate :race, to: :person, allow_nil: true
  delegate :ethnicity, to: :person, allow_nil: true
  delegate :language_code, to: :person, allow_nil: true
  delegate :is_tobacco_user, to: :person, allow_nil: true
  delegate :is_incarcerated, to: :person, allow_nil: true
  delegate :tribal_id, to: :person, allow_nil: true
  delegate :tribal_state, to: :person, allow_nil: true
  delegate :tribal_name, to: :person, allow_nil: true
  delegate :tribe_codes, to: :person, allow_nil: true
  delegate :is_disabled, to: :person, allow_nil: true
  delegate :citizen_status, to: :person, allow_nil: true
  delegate :indian_tribe_member, to: :person, allow_nil: true
  delegate :naturalized_citizen, to: :person, allow_nil: true
  delegate :eligible_immigration_status, to: :person, allow_nil: true
  delegate :is_dc_resident?, to: :person, allow_nil: true
  delegate :ivl_coverage_selected, to: :person
  delegate :is_applying_coverage, to: :person, allow_nil: true
  delegate :age_off_excluded, to: :person, allow_nil: true

  validates_presence_of :person_id, :is_primary_applicant, :is_coverage_applicant

  associated_with_one :person, :person_id, "Person"

  def former_family=(new_former_family)
    raise ArgumentError.new("expected Family") unless new_former_family.is_a?(Family)
    self.former_family_id = new_former_family._id
    @former_family = new_former_family
  end

  def former_family
    return @former_family if defined? @former_family
    @former_family = Family.find(former_family_id) unless former_family_id.blank?
  end

  def parent
    raise "undefined parent family" unless family
    self.family
  end

  def households
    # TODO parent.households.coverage_households.where()
  end

  def broker=(new_broker)
    return unless new_broker.is_a? BrokerRole
    self.broker_role_id = new_broker._id
  end

  def broker
    BrokerRole.find(self.broker_role_id) unless self.broker_role_id.blank?
  end

  def is_primary_applicant?
    self.is_primary_applicant
  end

  def is_consent_applicant?
    self.is_consent_applicant
  end

  def is_coverage_applicant?
    self.is_coverage_applicant
  end

  def age_on(date)
    age = date.year - dob.year
    if date.month < dob.month || (date.month == dob.month && date.day < dob.day)
      age - 1
    else
      age
    end
  end

  def is_active?
    self.is_active
  end

  def primary_relationship
    if is_primary_applicant?
      "self"
    else
      family.primary_applicant_person.find_relationship_with(person) unless family.primary_applicant_person.blank? || person.blank?
    end
  end

  def relationship
    primary_relationship
  end

  def reactivate!(relationship)
    family.primary_applicant_person.ensure_relationship_with(person, relationship)
    family.add_family_member(person)
  end

  def update_relationship(relationship)
    return if (primary_relationship == relationship)
    family.remove_family_member(person)
    self.reactivate!(relationship)
    family.save!
  end

  def self.find(family_member_id)
    return [] if family_member_id.nil?
    family = Family.where("family_members._id" => BSON::ObjectId.from_string(family_member_id)).first
    family.family_members.detect { |member| member._id.to_s == family_member_id.to_s } unless family.blank?
  end

  def latest_determined_evidence_pipeline(evidence_key)
    [
      { '$match' => { 'family_id' => family.id } },
      { '$unwind' => '$applicants' },
      { '$match' => { 'applicants.family_member_id' => id } },
      { '$unwind' => '$applicants.eligibilities' },
      { '$unwind' => '$applicants.eligibilities.evidences' },
      { '$match' => { 'applicants.eligibilities.evidences.key' => evidence_key } },
      { '$sort' => { 'applicants.eligibilities.evidences.created_at' => -1 } },
      { '$limit' => 1 },
      { '$project' => {
        'evidence_id' => '$applicants.eligibilities.evidences._id',
        'evidence_created_at' => '$applicants.eligibilities.evidences.created_at',
        'application_id' => '$_id',
        'application_type' => '$_type',
        '_id' => 0
      } }
    ]
  end

  def find_latest_determined_application_with_evidence_key(evidence_key)
    # Single aggregation pipeline that searches both collections efficiently
    pipeline = latest_determined_evidence_pipeline(evidence_key)

    # Individual Market Applications
    individual_result = IndividualMarket::Application.collection.aggregate([
      { '$match' => { 'current_state' => :determined } }
    ] + pipeline).first

    # Financial Assistance Applications
    fa_result = FinancialAssistance::Application.collection.aggregate([
      { '$match' => { 'aasm_state' => 'determined' } }
    ] + pipeline).first

    # Find the most recent evidence
    latest_result = [individual_result, fa_result].compact.max_by { |result| result['evidence_created_at'] }
    return nil if latest_result.nil?

    # Use the evidence ID to directly query for the evidence object
    evidence_id = latest_result['evidence_id']
    application_id = latest_result['application_id']
    application_type = latest_result['application_type']

    # Single targeted query to get just the evidence
    application = if application_type == 'IndividualMarket::Application'
                    IndividualMarket::Application.find(application_id)
                  else
                    FinancialAssistance::Application.find(application_id)
                  end

    return nil unless application

    application.fetch_evidence(evidence_id, id)
  end

  private

  def family_member_created
    deactivate_tax_households unless qhp_application_feature_enabled?
    create_financial_assistance_applicant unless qhp_application_feature_enabled?
    publish_private_family_member_created_event if EnrollRegistry.feature_enabled?(:async_publish_updated_families)
  end

  def publish_private_family_member_created_event
    event(
      'events.private.family_member_created',
      attributes: { family: family },
      headers: { after_updated_at: convert_time_to_string(created_at) }
    )&.success&.publish
  end

  def notify_family
    return if EnrollRegistry.feature_enabled?(:async_publish_updated_families)

    return unless EnrollRegistry.feature_enabled?(:check_for_crm_updates)
    return unless family
    family.set(crm_notifiction_needed: true)
  end

  def create_financial_assistance_applicant
    ::Operations::FinancialAssistance::CreateOrUpdateApplicant.new.call({family_member: self, event: :family_member_created}) if ::EnrollRegistry.feature_enabled?(:financial_assistance)
  rescue StandardError => e
    Rails.logger.error {"FAA Engine: Unable to do action Operations::FinancialAssistance::CreateOrUpdateApplicant for family_member with object_id: #{self.id} due to #{e.message}"}
  end

  def family_member_updated
    return if qhp_application_feature_enabled?

    deactivate_tax_households
    delete_financial_assistance_applicant
    create_financial_assistance_applicant
  end

  def delete_financial_assistance_applicant
    ::Operations::FinancialAssistance::DropApplicant.new.call({family_member: self}) if ::EnrollRegistry.feature_enabled?(:financial_assistance)
  rescue StandardError => e
    Rails.logger.error {"FAA Engine: Unable to do action Operations::FinancialAssistance::DropApplicant for family_member with object_id: #{self.id} due to #{e.message}"}
  end

  def deactivate_tax_households
    return unless family.persisted?

    family.deactivate_financial_assistance(TimeKeeper.date_of_record)
    return if family.active_household.latest_active_tax_household_with_year(TimeKeeper.date_of_record.year).blank?

    Operations::Households::DeactivateFinancialAssistanceEligibility.new.call(params: {
                                                                                deactivate_action_type: 'current_and_prospective', family_id: family.id, date: TimeKeeper.date_of_record
                                                                              })
  rescue StandardError => e
    Rails.logger.error {"Unable to do action Operations::Households::DeactivateFinancialAssistanceEligibility for family_member with object_id: #{self.id} due to #{e.message}"}
  end

  def product_factory
    ::BenefitMarkets::Products::ProductFactory
  end

  def no_duplicate_family_members
    return unless family
    family.family_members.group_by { |appl| appl.person_id }.select { |k, v| v.size > 1 }.each_pair do |k, v|
      errors.add(:family_members, "Duplicate family_members for person: #{k}\n")
    end
  end
end
