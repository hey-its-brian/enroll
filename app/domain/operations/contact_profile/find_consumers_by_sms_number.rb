# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module ContactProfile
    # Given an SMS number, resolve it to a (potentially empty) list of consumers.
    class FindConsumersBySmsNumber
      include Dry::Monads[:do, :result, :try]
      include EventSource::Command

      def call(phone_number)
        search_numbers = yield normalize_number_for_search(phone_number)
        find_consumers_by_numbers(search_numbers)
      end

      protected

      def normalize_number_for_search(phone_number)
        Try do
          parsed_number = Phonelib.parse(phone_number)
          [
            {
              kind: "mobile",
              full_phone_number: {
                "$in" => [parsed_number.e164.delete_prefix("+#{parsed_number.country_code}"), parsed_number.e164.delete_prefix("+"), parsed_number.e164]
              }
            },
            {
              kind: "mobile",
              country_code: parsed_number.country_code,
              area_code: parsed_number.national_number[0..2],
              number: parsed_number.national_number[-7..]
            }
          ]
        end.to_result
      end

      def find_consumers_by_numbers(search_number_criteria)
        Success(
          Person.where(
            phones: {
              "$elemMatch" => { "$or" => search_number_criteria }
            },
            :consumer_role => { "$exists" => true }
          )
        )
      end
    end
  end
end