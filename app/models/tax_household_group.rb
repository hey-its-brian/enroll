# frozen_string_literal: true

# Persistence class to group TaxHouseholds on each financial assistance determination.
class TaxHouseholdGroup
  include Mongoid::Document
  include Mongoid::Timestamps
  include ::ResourceRegistryHelper

  SOURCE_KINDS = %w[Curam Admin Renewals Faa Ffe qhp].freeze

  embedded_in :family

  field :source, type: String

  # @!attribute [rw] application_id
  #   @deprecated This field is deprecated. Initially, this field was added to store the application's BSON ID. Instead, we ended up storing the application's HBX ID for this field.
  #               To make the code more consistent, we added the `application_hbx_id` field to store the HBX ID of the application.
  #   @return [BSON::ObjectId] the BSON ID of the application
  field :application_id, type: BSON::ObjectId

  # @!attribute [rw] application_hbx_id
  #   @return [String] the HBX ID of the application
  #   @deprecated This field was initially used to store the HBX ID of the application.
  #               Moving forward, we will use the `application_gid` field to store the global identifier (GID) of the application as
  #               there are different types of applications (e.g., FinancialAssistance::Application, IndividualMarket::Application) that can be associated with a TaxHouseholdGroup.
  field :application_hbx_id, type: String

  # @!attribute [rw] application_gid
  #   @return [String] the global identifier (GID) of the application
  #   This field is used to store the GID of the application, which is a unique identifier across different systems.
  #   It is useful for referencing the application in a globally unique manner.
  field :application_gid, type: String

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

  # Returns the application associated with this tax household group.
  # It first checks if the application_gid is present and uses it to locate the application.
  # If the application_gid is not present, it checks for application_hbx_id and retrieves the application using that.
  #
  # @return [FinancialAssistance::Application, IndividualMarket::Application, nil] the associated application or nil if not found
  def application
    return @application if defined?(@application)

    @application = if qhp_application_feature_enabled?
                     GlobalID::Locator.locate(application_gid)
                   else
                     ::FinancialAssistance::Application.where(hbx_id: application_hbx_id).first
                   end
  end

  # Retrieves the type of the application for this tax household group.
  #
  # This method checks the class of the application and returns a string
  # representing its type: 'faa' for Financial Assistance applications, 'qhp' for
  # Individual Market applications, or nil if the type is not recognized.
  #
  # @return [String, nil] The type of the latest application ('faa', 'qhp', or nil)
  def application_type
    return nil unless application_gid

    case application.class
    when FinancialAssistance::Application
      'faa'
    when IndividualMarket::Application
      'qhp'
    end
  end

  private

  def generate_hbx_id
    write_attribute(:hbx_id, HbxIdGenerator.generate_tax_household_group_id) if hbx_id.blank?
  end
end
