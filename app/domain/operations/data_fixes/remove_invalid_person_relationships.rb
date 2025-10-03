# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# ::Operations::DataFixes::RemoveInvalidPersonRelationships.new.call({person_hbx_id: person_hbx_id})
module Operations
  module DataFixes
    # This operation removes invalid person relationships for a given person
    # where the related person record does not exist.
    class RemoveInvalidPersonRelationships
      include Dry::Monads[:do, :result]

      def call(params)
        person_hbx_id = yield validate(params)
        person        = yield fetch_person(person_hbx_id)
        result        = yield remove_invalid_relationships(person)

        Success(result)
      end

      private

      def validate(params)
        return Failure("person_hbx_id is missing") unless params[:person_hbx_id].present?

        Success(params[:person_hbx_id])
      end

      def fetch_person(person_hbx_id)
        result = ::Operations::People::Find.new.call({person_hbx_id: person_hbx_id})
        return result if result.success?

        Failure(result.failure)
      end

      def remove_invalid_relationships(person)
        return Success("No relationships to clean") if person.person_relationships.blank?

        relationship_ids = person.person_relationships.map(&:relative_id).compact
        existing_ids     = Person.where(:_id.in => relationship_ids).pluck(:_id)
        missing_ids      = relationship_ids - existing_ids

        return Success("No invalid relationships found") if missing_ids.blank?

        # Delete embedded relationships without triggering callbacks/validations.
        person.person_relationships.where(:relative_id.in => missing_ids).delete_all

        Success("Successfully removed #{missing_ids.size} invalid person relationships for person #{person.hbx_id}")
      rescue StandardError => e
        Failure("Failed to remove invalid relationships: #{e.message}")
      end
    end
  end
end


