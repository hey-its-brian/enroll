# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  # This class takes in empty args and removes invalid person relationships where the related person record does not exist.
  class RemoveInvalidPersonRelationships
    include Dry::Monads[:do, :result]

    def call(_params)
      invalid_person_relationships = yield fetch_invalid_person_relationships
      result                       = yield process_invalid_relationships(invalid_person_relationships)

      Success(result)
    end

    private

    def fetch_invalid_person_relationships
      invalid_relationships = Person.collection.aggregate([
        { "$unwind": "$person_relationships" },
        {
          "$lookup": {
            from: "people",
            localField: "person_relationships.relative_id",
            foreignField: "_id",
            as: "relative_match"
          }
        },
        { "$match": { "relative_match": { "$size": 0 } } },
        {
          "$project": {
            person_id: "$_id",
            invalid_relationship: "$person_relationships"
          }
        }
      ])
      Success(invalid_relationships)
    end

    def process_invalid_relationships(invalid_relationships)
      date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
      updated_count = 0
      filepath = Rails.root.join("removed_invalid_person_relationships_#{date}.csv")

      CSV.open(filepath, 'w', force_quotes: true) do |csv|
        csv << ['Primary Person Hbx Id', 'Invalid Relationship Kind', 'Invalid Relative Id', 'Created At']
        invalid_relationships.each do |rel|
          person = Person.find(rel[:person_id])
          next unless person

          invalid_relationship = person.person_relationships.find(rel[:invalid_relationship][:_id])
          next unless invalid_relationship

          csv << [person.hbx_id, invalid_relationship.kind, invalid_relationship.relative_id, invalid_relationship.created_at]

          invalid_relationship.destroy if Person.where(id: invalid_relationship.relative_id).empty?
          updated_count += 1
        rescue Mongoid::Errors::DocumentNotFound => e
          Rails.logger.error "Could not find person or relationship for data: #{rel}. Error: #{e.message}"
        rescue StandardError => e
          Rails.logger.error "Failed to process invalid relationship for person #{rel[:person_id]}: #{e.message}"
        end
      end
      Success("Successfully removed #{updated_count} invalid relationships and generated CSV file: #{filepath}")
    end
  end
end