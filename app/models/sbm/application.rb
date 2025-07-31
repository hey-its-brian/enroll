# frozen_string_literal: true

module Sbm
  # @abstract Base class for different types of applications in the system
  #   following the Single Table Inheritance (STI) pattern
  # @note Subclasses include: IndividualMarket::Application, FinancialAssistance::Application,
  #   and ShopMarket::Application
  # @note The _type field is automatically created by Mongoid for STI
  # @example Creating a specific application type using _type field
  #   family.applications.build(_type: 'IndividualMarket::Application')
  class Application
    include Mongoid::Document
    include Mongoid::Timestamps
    include GlobalID::Identification

    # @!attribute family
    #   @return [Family] The family this application belongs to
    belongs_to :family, class_name: 'Family', index: true

    before_create :assign_hbx_id

    # @!index [Hash] Creates a compound index on current_state, family_id, assistance_year, and submitted_at fields.
    # @param current_state [Integer] The application state, with 1 indicating ascending order
    # @param family_id [Integer] The family identifier, with 1 indicating ascending order
    # @param assistance_year [Integer] The assistance year, with -1 indicating descending order
    # @param submitted_at [Date] The submission timestamp, with -1 indicating descending order
    # @note This index improves queries that filter by state and family_id and sort by creation date
    index({ current_state: 1, family_id: 1, assistance_year: -1, submitted_at: -1 })

    # @!index [Hash] Creates an index on the hbx_id field
    # @param hbx_id [Integer] The field to index, with 1 indicating ascending order
    # @option options [Boolean] :unique (true) Ensures the index is unique
    index({ hbx_id: 1 }, { unique: true })

    # @!scope class
    # @return [Mongoid::Criteria] The most recent determined IndividualMarket::Application based on assistance year and submitted_at
    scope :newest_determined_by_family_id, lambda { |family_id|
      where(current_state: :determined, family_id: family_id).order_by(assistance_year: -1, submitted_at: -1).limit(1)
    }

    # @!scope class
    # @return [Mongoid::Criteria] The most recent Sbm::Application based on creation timestamp
    scope :newest, -> { order_by(created_at: :desc).limit(1) }

    # @!scope class
    # @return [Mongoid::Criteria] The most recent Sbm::Application based on hbx_id
    scope :by_hbx_id, ->(hbx_id) { where(hbx_id: hbx_id) }

    # @!attribute current_state
    # @return [Symbol] The current state of the application. This is a replacement for aasm_state
    field :current_state, type: Symbol, default: :initial

    # @!attribute hbx_id
    # @return [String] The unique identifier for the application
    field :hbx_id, type: String

    private

    # Assigns a unique hbx_id to the application if it is not already set
    #
    # @return [void]
    # @note We are using the same sequence generator as 'faa_application_id' to generate the hbx_id.
    #       This is to ensure that the hbx_id is unique across different types of applications.
    #       This makes sure that we can just use hbx_id as a unique identifier for the application instead of having a combination of hbx_id and application_type(FAA or QHP).
    def assign_hbx_id
      self.hbx_id ||= ::HbxIdGenerator.generate_application_id
    end
  end
end
