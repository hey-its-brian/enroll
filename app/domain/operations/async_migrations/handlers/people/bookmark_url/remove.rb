# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    module Handlers
      module People
        module BookmarkURL
          # Handler to remove person bookmark URLs.
          class Remove
            include Dry::Monads[:do, :result]
            include EventSource::Command
            include ::ResourceRegistryHelper

            def call(params)
              person_id = yield validate(params)
              person = yield find_person(person_id)
              result = yield remove_bookmark_url(person)
              yield publish(result)
              Success(result[2])
            rescue StandardError => e
              Failure("Failed to process person with id #{params[:document_id]}: #{e.message}")
            end

            private

            # Validates the input parameters.
            # @param document_id [String] The document ID to validate.
            # @return [Dry::Monads::Result] The result of the validation.
            def validate(params)
              return Failure("Params must be a hash") unless params.is_a?(Hash)
              return Failure("Document id must be of valid BSON::ObjectId format") unless BSON::ObjectId.legal?(params[:document_id])

              Success(params[:document_id])
            end

            def find_person(person_id)
              result = Person.where(:id => person_id).first
              return Failure("No person found with id #{person_id}") if result.nil?

              Success(result)
            end

            def remove_bookmark_url(person)
              return Success([person.hbx_id, false, "Person hbx_id: #{person.hbx_id} does not have a consumer role"]) if person.consumer_role.blank?
              return Success([person.hbx_id, false, "Person hbx_id: #{person.hbx_id} is not RIDP verified"]) unless person.consumer_role.identity_verified? || person.consumer_role.application_verified?
              return Success([person.hbx_id, false, "Person hbx_id: #{person.hbx_id} is not associated with a user"]) if person.user.blank?
              return Success([person.hbx_id, false, "User with person hbx_id: #{person.hbx_id} is not identity verified"]) unless person.user.identity_verified?

              person.consumer_role.set(bookmark_url: nil, admin_bookmark_url: nil)
              Success([person.hbx_id, true, "Successfully removed bookmark URL and admin bookmark URL"])
            end

            def publish(row)
              csv_headers = [
                            "Person HBX ID",
                            "Migration Result",
                            "Message"
                            ]

              event = event("events.migration_results.enqueue_result", attributes: {csv_file_name: "bookmark_url_report", csv_headers: csv_headers, csv_row: row})

              result = if event.success?
                         event.success.publish
                         true
                       else
                         false
                       end

              result ? Success("BookMark URL updated successfully and published to migration results") : Failure("Failed to publish migration results event")
            end
          end
        end
      end
    end
  end
end
