# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module DataFixes
    # This operation is responsible for ethnicity for FAA applications.
    class FixEthnicityForPerson
      include Dry::Monads[:do, :result]

      def call(person_hbx_id:)
        person = yield fetch_person(person_hbx_id)
        yield adjust_ethnicity(person)
        Success(person)
      end

      def adjust_ethnicity(person)
        ethnicity = person.ethnicity.nil? ? [] : person.ethnicity.compact.reject(&:empty?)
        person.set(ethnicity: ethnicity)

        Success(person)
      end

      private

      def fetch_person(person_hbx_id)
        person = Person.find_by hbx_id: person_hbx_id
        return Failure(:person_not_found) unless person
        Success(person)
      rescue Mongoid::Errors::DocumentNotFound
        Failure(:person_not_found)
      end
    end
  end
end