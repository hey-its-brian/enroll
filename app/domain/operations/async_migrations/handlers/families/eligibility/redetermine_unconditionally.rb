# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        module Eligibility
          # Operation handler to unconditionally redetermine a family's eligibility
          # and publish a reporting row with previous vs current determination data.
          #
          # Responsibilities:
          # - Validate and resolve the target Family by document_id (BSON::ObjectId)
          # - Ensure the Family has an existing eligibility determination
          # - Build a new eligibility determination
          # - Emit a reporting event with CSV headers and row data for analytics
          #
          # Side effects:
          # - Writes logs to a date-stamped file under Rails.root/log
          # - Publishes an event to `events.migration_results.enqueue_result`
          #
          # Usage:
          #   operation = Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineUnconditionally.new
          #   operation.call(document_id: "64fd2bdab1c9d44f3f000001")
          #
          # Errors are returned as Dry::Monads::Failure with human-readable messages.
          class RedetermineUnconditionally
            include Dry::Monads[:do, :result]
            include EventSource::Command

            # CSV headers used by the reporting event payload.
            #
            # @return [Array<String>]
            CSV_HEADERS = [
                  "Person HBX ID",
                  "Family HBX ID",
                  "Previous Determination Created At",
                  "Previous Determination Status",
                  "Previous Due Date",
                  "Previous Determination Application HBX ID",
                  "Current Determination Created At",
                  "Current Determination Status",
                  "Current Due Date",
                  "Current Determination Application HBX ID",
                  "Message"
            ].freeze

            # Validates input, initializes logging, loads the Family, confirms a prior
            # determination exists, attempts a new determination, composes a CSV row,
            # and publishes a reporting event.
            #
            # @param params [Hash] Options hash
            # @option params [String] :document_id The BSON::ObjectId string for the Family
            #
            # @return [Dry::Monads::Result]
            #   - Success(result) on successful publish
            #   - Failure(String) with reason message on any error
            #
            # @raise [StandardError] Internal logging or unexpected data errors are captured
            #   and returned as Failure; method does not re-raise.
            def call(params)
              validated_params = yield validate(params)
              family = yield find_family(validated_params[:document_id])
              previous_eligibility_determination, message = yield redetermine_eligibility(family)
              row = yield csv_row(previous_eligibility_determination, message, family)
              result = yield publish(row)

              Success(result)
            end

            private

            # Validates the input parameters
            #
            # @param params [Hash] Parameters for the operation
            # @return [Dry::Monads::Result] Success with validated params or Failure with error
            def validate(params)
              unless params.is_a?(Hash)
                logger.error("Params must be a hash")
                return Failure("Params must be a hash") unless params.is_a?(Hash)
              end

              unless BSON::ObjectId.legal?(params[:document_id])
                logger.error("Document id must be of valid BSON::ObjectId format")
                return Failure("Document id must be of valid BSON::ObjectId format")
              end

              Success(params)
            end

            # Resolves a Family by BSON document_id.
            #
            # @param document_id [String] BSON::ObjectId string
            #
            # @return [Dry::Monads::Result]
            #   - Success(Family) when found
            #   - Failure(String) when not found
            def find_family(document_id)
              family = ::Family.find(document_id)
              Success(family)
            rescue Mongoid::Errors::DocumentNotFound => _e
              logger.error("::Family not found for document id: #{document_id}")
              Failure("::Family not found for document id: #{document_id}")
            end

            # Builds a new eligibility determination for the given Family.
            #
            # Logs progress and returns a tuple containing the previous determination
            # and a status message that reflects success or failure of the rebuild.
            #
            # @param family [Family] Target family
            #
            # @return [Dry::Monads::Result]
            #   - Success([EligibilityDetermination, String]) previous determination and message
            #   - Failure(String) with error message when the determination fails unexpectedly
            def redetermine_eligibility(family)
              logger.info("Determining family eligibility for family: #{family.id}")

              # Store previous values for reporting
              previous_eligibility_determination = family.eligibility_determination
              result = ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
              family.reload
              message =
                if result.success?
                  "Successfully redetermined eligibility for family #{family.id}"
                else
                  "Unable to redetermine eligibility for family #{family.id} due to failure #{result.failure}"
                end

              logger.send(result.success? ? :info : :error, message)
              Success([previous_eligibility_determination, message])
            rescue StandardError => e
              message = "Error determining eligibility for Family: #{family.id} - #{e.message}"
              logger.error(message)
              Failure(message)
            end

            # Composes a CSV row for reporting, including previous and current determination details.
            #
            # This method resolves application HBX IDs via stored GIDs for both previous
            # and current determinations when available.
            #
            # @param previous_eligibility_determination [EligibilityDetermination, nil] Previous determination
            # @param message [String] Result message from determination step
            # @param family [Family] Target family
            #
            # @return [Dry::Monads::Result] Success(Hash) row data ready for publishing
            def csv_row(previous_eligibility_determination, message, family)
              primary = family.primary_person
              current_eligibility_determination = family.eligibility_determination

              row = [
                primary.hbx_id,
                family.hbx_assigned_id,
                previous_eligibility_determination&.created_at,
                previous_eligibility_determination&.outstanding_verification_status,
                previous_eligibility_determination&.outstanding_verification_earliest_due_date,
                GlobalID::Locator.locate(previous_eligibility_determination&.application_gid)&.hbx_id,
                current_eligibility_determination&.created_at,
                current_eligibility_determination&.outstanding_verification_status,
                current_eligibility_determination&.outstanding_verification_earliest_due_date,
                GlobalID::Locator.locate(current_eligibility_determination&.application_gid)&.hbx_id,
                message
            ]

              Success(row)
            end

            # Publishes the CSV row to the migration results event topic.
            #
            # Event name: `events.migration_results.enqueue_result`
            #
            # Attributes:
            # - csv_file_name: String id for grouping/reporting
            # - csv_headers: Array<String> matching CSV_HEADERS
            # - csv_row: Hash payload produced by csv_row
            #
            # @param row [Hash] Prepared reporting row
            #
            # @return [Dry::Monads::Result]
            #   - Success(:published) when event publishing succeeds
            #   - Failure(String) when event build or publish fails
            def publish(row)
              event = event(
                'events.migration_results.enqueue_result',
                attributes: {
                  csv_file_name: "redetermine_family_eligibility_unconditionally",
                  csv_headers: CSV_HEADERS,
                  csv_row: row
                }
              )
              if event.success?
                event.success.publish
                logger.info("Published family eligibility for reporting - #{event.success}")
                Success(:published)
              else
                logger.error("Failed to publish family eligibility for reporting - #{event.failure}")
                Failure("Failed to publish family eligibility for reporting - #{event.failure}")
              end
            end

            def logger
              @logger ||= Logger.new(
                "#{Rails.root}/log/redetermine_family_eligibility_unconditionally_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
              )
            end
          end
        end
      end
    end
  end
end
