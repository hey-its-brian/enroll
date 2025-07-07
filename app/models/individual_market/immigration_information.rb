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
    field :immigration_doc_statuses, type: Array

    def provided_information
      attributes.except("_id", "created_at", "updated_at", "subject").select { |_key, value| value.present? }.collect { |key, value| {label: key.titleize, display_value: standardize_display(value)} }
    end

    # Creates a copy of this immigration information for a new applicant
    #
    # @param [IndividualMarket::Applicant] new_applicant The applicant to associate the copied immigration information with
    # @return [IndividualMarket::ImmigrationInformation] The newly created immigration information with identical attributes
    # @example Copy immigration information to a new applicant
    #   immigration_info.copy_immigration_information(new_applicant)
    def copy_immigration_information(new_applicant)
      new_applicant.build_immigration_information(
        subject: subject,
        alien_number: alien_number,
        i94_number: i94_number,
        visa_number: visa_number,
        passport_number: passport_number,
        sevis_id: sevis_id,
        naturalization_number: naturalization_number,
        receipt_number: receipt_number,
        citizenship_number: citizenship_number,
        card_number: card_number,
        country_of_citizenship: country_of_citizenship,
        expiration_date: expiration_date,
        issuing_country: issuing_country,
        description: description,
        immigration_doc_statuses: immigration_doc_statuses
      )
    end

    private

    def standardize_display(value)
      return value.join(", ") if value.is_a?(Array)
      return value.strftime("%m/%d/%Y") if value.is_a?(Date) || value.is_a?(Time) || value.is_a?(DateTime)
      value
    end
  end
end
