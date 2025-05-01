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

    # @!index [Hash] Creates a compound index on current_state, family_id, assistance_year, and submitted_at fields.
    # @param current_state [Integer] The application state, with 1 indicating ascending order
    # @param family_id [Integer] The family identifier, with 1 indicating ascending order
    # @param assistance_year [Integer] The assistance year, with -1 indicating descending order
    # @param submitted_at [Date] The submission timestamp, with -1 indicating descending order
    # @note This index improves queries that filter by state and family_id and sort by creation date
    index({ current_state: 1, family_id: 1, assistance_year: -1, submitted_at: -1 })

    # @!scope class
    # @return [Mongoid::Criteria] The most recent determined IndividualMarket::Application based on assistance year and submitted_at
    scope :newest_determined_by_family_id, lambda { |family_id|
      where(current_state: :determined, family_id: family_id).order_by(assistance_year: -1, submitted_at: -1).limit(1)
    }

    # @!scope class
    # @return [Mongoid::Criteria] The most recent Sbm::Application based on creation timestamp
    scope :newest, -> { order_by(created_at: :desc).limit(1) }

    # @!attribute current_state
    # @return [Symbol] The current state of the application. This is a replacement for aasm_state
    field :current_state, type: Symbol, default: :initial
  end
end
