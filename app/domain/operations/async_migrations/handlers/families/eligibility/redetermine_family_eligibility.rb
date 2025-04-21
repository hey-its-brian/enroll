# frozen_string_literal: true

require "dry/monads"

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        module Eligibility
          # Redetermines family eligibility for families with Outstanding verification status
          # or families with people who are all not applying for coverage.
          #
          # This handler processes individual families by:
          # 1. Finding the family based on document_id
          # 2. Determining an appropriate effective date for eligibility
          # 3. Creating a new eligibility determination
          # 4. Publishing migration results for reporting
          #
          # @example Calling the handler
          #   Operations::AsyncMigrations::Handlers::Families::Eligibility::RedetermineFamilyEligibility.new.call(
          #     document_id: "5f4b8e3c1c9d440000000001"
          #   )
          class RedetermineFamilyEligibility
            include Dry::Monads[:do, :result]
            include EventSource::Command
            include LoggingHelper

            EVENT_DESTINATION = 'events.migration_results.enqueue_result'
            LOG_FILE_PREFIX = "redetermine_family_eligibility_initial_migration_handler"
            ENROLLED_STATES = ::HbxEnrollment::ENROLLED_STATUSES

            # Main entry point for the operation
            #
            # @param params [Hash] Parameters containing :document_id
            # @return [Dry::Monads::Result] Success with result or Failure with error message
            def call(params)
              validated_params = yield validate(params)
              @logger = yield initialize_logger
              family = yield find_family(validated_params[:document_id])
              _eligibility_check = yield check_for_eligibility(family, validated_params)
              result = yield redetermine_family_eligibility(family, validated_params)

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

            # Checks if a family is eligible for eligibility redetermination based on verification status,
            # coverage application status, and creation date threshold.
            #
            # A family is eligible for redetermination if:
            # 1. It has an 'outstanding' verification status
            # 2. All active family members are not applying for coverage
            # 3. The eligibility determination was created on or after the specified date threshold
            #
            # @param family [Family] The family to check eligibility for
            # @param params [Hash] Parameters that may contain date threshold information
            # @option params [Hash] :additional_params Additional parameters
            # @option params[:additional_params] [String] :date_threshold Date string in 'YYYY-MM-DD' format
            # @return [Dry::Monads::Result] Success with family if eligible, Failure with error message if not
            def check_for_eligibility(family, params)
              # Get and parse date threshold, defaulting to today if not provided
              date_threshold = params.dig(:additional_params, :date_threshold) || TimeKeeper.date_of_record.beginning_of_day.strftime('%Y-%m-%d')
              parsed_date = Date.parse(date_threshold)

              # Check for eligibility determination presence
              unless family.eligibility_determination.present?
                log_message("Family has no eligibility determination: #{family.hbx_assigned_id}", :error, @logger)
                return Failure("Family has no eligibility determination: #{family.hbx_assigned_id}")
              end

              # Extract required conditions
              eligibility_status = family.eligibility_determination.outstanding_verification_status
              is_any_member_applying_for_coverage = family.active_family_members.any?(&:is_applying_coverage)
              created_at = family.eligibility_determination.created_at&.to_date

              # Check if date comparison can be performed
              unless created_at.present?
                log_message("Family eligibility determination has no creation date: #{family.hbx_assigned_id}", :error, @logger)
                return Failure("Family eligibility determination has no creation date: #{family.hbx_assigned_id}")
              end

              # Verify all conditions are met
              if (eligibility_status == 'outstanding' || !is_any_member_applying_for_coverage) && created_at >= parsed_date
                Success(family)
              else
                reason = determine_failure_reason(eligibility_status, is_any_member_applying_for_coverage, created_at, parsed_date)
                log_message("Family not eligible for redetermination: #{family.hbx_assigned_id} - #{reason}", :error, @logger)
                Failure("Family not eligible for redetermination: #{family.hbx_assigned_id} - #{reason}")
              end
            end

            def determine_failure_reason(eligibility_status, is_any_member_applying_for_coverage, created_at, parsed_date)
              reasons = []
              reasons << "status is not outstanding" if eligibility_status != 'outstanding'
              reasons << "some members are applying for coverage" if  is_any_member_applying_for_coverage
              reasons << "determination created before threshold date" if created_at < parsed_date
              reasons.join(', ')
            end

            # Redetermines eligibility for a family
            #
            # @param family [Family] The family to process
            # @return [Dry::Monads::Result] Success with message or Failure with error
            def redetermine_family_eligibility(family, validated_params)
              log_message("Determining family eligibility for family: #{family.id}", :info, @logger)

              # Store previous values for reporting
              previous_determination_status = family.eligibility_determination&.outstanding_verification_status
              previous_due_date = family.eligibility_determination&.outstanding_verification_earliest_due_date

              # Determine effective date and build family determination
              effective_date = determine_effective_date(family, validated_params)
              result = ::Operations::Eligibilities::BuildFamilyDetermination.new.call(
                family: family,
                effective_date: effective_date
              )

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

            # Determines the effective date for eligibility based on available data
            #
            # @param family [Family] The family being processed
            # @return [Date] The effective date to use
            def determine_effective_date(family, validated_params)
              assistance_year = validated_params.dig(:additional_params, :assistance_year)
              assistance_year ||= TimeKeeper.date_of_record.year
              active_health_enrollments = family.hbx_enrollments.by_health.where(:aasm_state.in => ENROLLED_STATES)
              determined_applications = ::FinancialAssistance::Application.determined
                                                                          .by_year(assistance_year)
                                                                          .where(family_id: family.id)
              if active_health_enrollments.any?
                active_health_enrollments.first.effective_on
              elsif determined_applications.any?
                determined_applications.last.effective_date
              else
                TimeKeeper.date_of_record
              end
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
