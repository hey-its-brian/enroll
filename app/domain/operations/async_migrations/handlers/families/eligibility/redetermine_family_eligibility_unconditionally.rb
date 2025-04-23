# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        module Eligibility
          # Redetermines family eligibility.
          #
          # This handler processes individual families by:
          # 1. Finding the family based on document_id
          # 3. Creating a new eligibility determination
          # 4. Publishing migration results for reporting
          #
          # @example Calling the handler
          #   Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibilityUnconditionally.new.call(
          #     document_id: "5f4b8e3c1c9d440000000001"
          #   )
          class RedetermineFamilyEligibilityUnconditionally
            include Dry::Monads[:do, :result]
            include EventSource::Command
            include LoggingHelper

            EVENT_DESTINATION = 'events.migration_results.enqueue_result'
            LOG_FILE_PREFIX = "redetermine_family_eligibility_unconditionally_initial_migration_handler"

            # Main entry point for the operation
            #
            # @param params [Hash] Parameters containing :document_id
            # @return [Dry::Monads::Result] Success with result or Failure with error message
            def call(params)
              validated_params = yield validate(params)
              @logger = yield initialize_logger
              family = yield find_family(validated_params[:document_id])
              family = yield check_for_eligibility(family)
              result = yield redetermine_family_eligibility(family)

              Success(result)
            end

            private

            # Initializes the logger.
            #
            # @return [Dry::Monads::Result] Success with logger or Failure with error
            def initialize_logger
              Success(
                Logger.new(
                  "#{Rails.root}/log/#{LOG_FILE_PREFIX}_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.log"
                )
              )
            rescue StandardError => e
              Failure("Error initializing logger: #{e.message}")
            end

            # Validates the input parameters
            #
            # @param params [Hash] Parameters for the operation
            # @return [Dry::Monads::Result] Success with validated params or Failure with error
            def validate(params)
              return Failure("Params must be a hash") unless params.is_a?(Hash)
              return Failure("Document id must be of valid BSON::ObjectId format") unless BSON::ObjectId.legal?(params[:document_id])

              Success(params)
            end

            # Finds the family by document_id
            #
            # @param document_id [String] The BSON id of the Family
            # @return [Dry::Monads::Result] Success with Family or Failure with error
            def find_family(document_id)
              family = ::Family.find(document_id)
              Success(family)
            rescue Mongoid::Errors::DocumentNotFound => _e
              Failure("::Family not found for document id: #{document_id}")
            end

            # Checks if a family has an existing eligibility determination.
            #
            # @param family [Family] The family to check eligibility for
            # @return [Dry::Monads::Result] Success with family if eligible, Failure with error message if not
            def check_for_eligibility(family)
              unless family.eligibility_determination.present?
                log_message("Family has no eligibility determination: #{family.hbx_assigned_id}", :error, @logger)
                return Failure("Family has no eligibility determination: #{family.hbx_assigned_id}")
              end

              Success(family)
            end

            # Redetermines eligibility for a family
            #
            # @param family [Family] The family to process
            # @return [Dry::Monads::Result] Success with message or Failure with error
            def redetermine_family_eligibility(family)
              log_message("Determining family eligibility for family: #{family.id}", :info, @logger)

              # Store previous values for reporting
              previous_determination_status = family.eligibility_determination&.outstanding_verification_status
              previous_due_date = family.eligibility_determination&.outstanding_verification_earliest_due_date

              result = ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)

              # Report results
              message = result_message(result, family)
              enqueue_family_eligibility_row(
                previous_determination_status,
                previous_due_date,
                message,
                family
              )

              log_message(message, :info, @logger)
              result
            rescue StandardError => e
              message = "Error determining eligibility for Family: #{family.id} - #{e.message}"
              log_message(message, :error, @logger)
              Failure(message)
            end

            # Formats a message based on the result
            #
            # @param result [Dry::Monads::Result] The result of the family determination
            # @param family [Family] The family being processed
            # @return [String] The formatted message
            def result_message(result, family)
              if result.success?
                "Successfully redetermined eligibility for family #{family.id}"
              else
                "Unable to redetermine eligibility for family #{family.id} due to failure #{result.failure}"
              end
            end

            # Creates and publishes reporting data
            #
            # @param previous_determination_status [String] The previous determination status
            # @param previous_due_date [Date] The previous due date
            # @param message [String] The result message
            # @param family [Family] The family being processed
            def enqueue_family_eligibility_row(previous_determination_status, previous_due_date, message, family)
              primary = family.primary_person
              current_determination_status = family.eligibility_determination&.outstanding_verification_status
              current_due_date = family.eligibility_determination&.outstanding_verification_earliest_due_date

              row = {
                person_hbx_id: primary.hbx_id,
                family_hbx_id: family.hbx_assigned_id,
                previous_determination_status: previous_determination_status,
                previous_due_date: previous_due_date,
                current_determination_status: current_determination_status,
                current_due_date: current_due_date,
                message: message
              }

              publish_family_eligibility_row(row)
            end

            # Publishes family eligibility data to event queue
            #
            # @param row [Hash] The data to publish
            def publish_family_eligibility_row(row)
              event = event(EVENT_DESTINATION, attributes: row)

              if event.success?
                event.success.publish
                @logger.info "Published family eligibility for reporting - #{event.success}" unless Rails.env.test?
              else
                @logger.error "Failed to publish family eligibility for reporting #{row[:family_hbx_id]} - #{event.failure}" unless Rails.env.test?
              end
            end
          end
        end
      end
    end
  end
end
