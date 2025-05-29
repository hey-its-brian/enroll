# frozen_string_literal: true

module Forms
  module IndividualMarket
    # Form for managing immigration information for an applicant
    class ImmigrationInformationForm
      include ActiveModel::Model

      attr_accessor :subject,
                    :alien_number,
                    :i94_number,
                    :visa_number,
                    :passport_number,
                    :sevis_id,
                    :naturalization_number,
                    :receipt_number,
                    :citizenship_number,
                    :card_number,
                    :country_of_citizenship,
                    :expiration_date,
                    :issuing_country,
                    :description,
                    :id

      def to_h
        {
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
          description: description
        }.compact
      end
    end
  end
end