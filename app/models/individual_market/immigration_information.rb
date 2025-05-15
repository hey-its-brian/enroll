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

    # Enable the commented fields below or add new fields (more descriptive) as needed.
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
    # field :status, type: String
    # field :comment, type: String
    field :description, type: String

    # Below are all the fields that are present in the VlpDocument model in the main application.
    # field :title, type: String, default: "untitled"
    # field :creator, type: String, default: EnrollRegistry[:enroll_app].setting(:publisher).item
    # field :subject, type: String
    # field :description, type: String
    # field :publisher, type: String, default: EnrollRegistry[:enroll_app].setting(:publisher).item
    # field :contributor, type: String
    # field :date, type: Date
    # field :type, type: String, default: "text"
    # field :format, type: String, default: "application/octet-stream"
    # field :identifier, type: String
    # field :source, type: String, default: "enroll_system"
    # field :language, type: String, default: "en"
    # field :relation, type: String
    # field :coverage, type: String
    # field :rights, type: String
    # field :tags, type: Array, default: []
    # field :size, type: String
    # field :doc_identifier, type: String
    # field :alien_number, type: String
    # field :i94_number, type: String
    # field :visa_number, type: String
    # field :passport_number, type: String
    # field :sevis_id, type: String
    # field :naturalization_number, type: String
    # field :receipt_number, type: String
    # field :citizenship_number, type: String
    # field :card_number, type: String
    # field :country_of_citizenship, type: String
    # field :expiration_date, type: DateTime
    # field :issuing_country, type: String
    # field :status, type: String, default: "not submitted"
    # field :verification_type
    # field :comment, type: String
  end
end
