# frozen_string_literal: true

module IndividualMarket
  # This class represents immigration information for an applicant.
  # This is replacement for VlpDocument model in the main application.
  class ImmigrationInformation
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute applicant
    #   @return [IndividualMarket::Applicant] The applicant to which this immigration information belongs to
    embedded_in :applicant, class_name: 'IndividualMarket::Applicant'

    field :subject, type: String
    field :alien_number, type: String
    field :i94_number, type: String
    field :visa_number, type: String
    field :passport_number, type: String
    field :sevis_id, type: String
    field :naturalization_number, type: String
    field :receipt_number, type: String
    field :citizenship_number, type: String
    field :card_number, type: String
    field :country_of_citizenship, type: String
    field :expiration_date, type: Date
    field :issuing_country, type: String
    field :description, type: String

    def provided_information
      attributes.except("_id", "created_at", "updated_at", "subject").select { |_key, value| value.present? }.collect { |key, value| {label: key.titleize, display_value: value} }
    end
  end
end
