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

    # @!attribute family
    #   @return [Family] The family this application belongs to
    belongs_to :family, class_name: 'Family', index: true

    # @!index [Hash] Creates a compound index on aasm_state, family_id, and created_at fields
    # @param current_state [Integer] The application state, with 1 indicating ascending order
    # @param family_id [Integer] The family identifier, with 1 indicating ascending order
    # @param created_at [Integer] The creation timestamp, with -1 indicating descending order
    # @note This index improves queries that filter by state and family_id and sort by creation date
    index({ current_state: 1, family_id: 1, created_at: -1 })

    # @!scope class
    # @return [Mongoid::Criteria] The most recent determined Sbm::Application based on creation timestamp
    scope :newest_determined_by_family_id, lambda { |family_id|
      where(current_state: 'determined', family_id: family_id).order(created_at: :desc).limit(1)
    }

    # @!scope class
    # @return [Mongoid::Criteria] The most recent Sbm::Application based on creation timestamp
    scope :newest, -> { order_by(created_at: :desc).limit(1) }

    # @!attribute current_state
    # @return [Symbol] The current state of the application. This is a replacement for aasm_state
    field :current_state, type: Symbol, default: :initial
  end
end
