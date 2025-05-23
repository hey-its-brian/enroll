# frozen_string_literal: true

# Persistence class to group TaxHouseholds on each financial assistance determination.
class TaxHouseholdGroup
  include Mongoid::Document
  include Mongoid::Timestamps

  SOURCE_KINDS = %w[Curam Admin Renewals Faa Ffe qhp].freeze

  embedded_in :family

  field :source, type: String

  # @!attribute [rw] application_id
  #   @deprecated This field is deprecated. Initially, this field was added to store the application's BSON ID. Instead, we are now persisting the application's HBX ID using {#application_hbx_id}.
  #   @return [BSON::ObjectId] the BSON ID of the application
  field :application_id, type: BSON::ObjectId

  # @!attribute [rw] application_hbx_id
  #   @return [String] the HBX ID of the application
  field :application_hbx_id, type: String

  field :start_on, type: Date
  field :end_on, type: Date
  field :assistance_year, type: Integer
  field :determined_on, type: Date

  field :hbx_id, type: String

  validates_presence_of :start_on
  validates :source,
            allow_blank: false,
            inclusion: { in: SOURCE_KINDS,
                         message: "%{value} is not a valid source kind" }

  # Validates that the HBX ID is unique within the TaxHouseholdGroup model.
  # @!attribute [r] hbx_id
  #   @return [String] the unique identifier for the tax household group
  validates_uniqueness_of :hbx_id, message: 'HBX ID must be unique'

  embeds_many :tax_households, cascade_callbacks: true

  before_save :generate_hbx_id

  index({ application_id:  1 })
  index({ start_on:  1 })
  index({ end_on:  1 })
  index({ assistance_year:  1 })
  index({ :"tax_households._id" => 1 })

  # Scopes
  scope :by_year,   ->(year) { where(assistance_year: year) }
  scope :active,    ->{ where(end_on: nil) }
  scope :inactive,  ->{ where(:end_on.ne => nil) }
  scope :current_and_prospective_by_year, ->(year) { where(:assistance_year.gte => year) }

  def latest_active_tax_household_with_year(year)
    tax_households.tax_household_with_year(year).active_tax_household.order_by(:created_at.desc).first
  end

  # @return [FinancialAssistance::Application, nil] the application associated with the given HBX ID, or nil if not found
  def application
    return if application_hbx_id.blank?

    ::FinancialAssistance::Application.by_hbx_id(application_hbx_id).first
  end

  private

  def generate_hbx_id
    write_attribute(:hbx_id, HbxIdGenerator.generate_tax_household_group_id) if hbx_id.blank?
  end
end
