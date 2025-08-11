# frozen_string_literal: true

module FinancialAssistance
  module Operations
    module Evidences
      # Utility methods for handling hub calls
      #
      # This module provides common functionality for hub communication, including
      # parameter validation, application processing, event publishing, and error handling.
      # It's designed to be included in operation classes that interact with external
      # verification services.
      #
      # @example Including in an operation class
      #   class CallHub
      #     include HubCallUtils
      module HubCallUtils
        include Dry::Monads[:do, :result]

        # @param params [Hash] Input parameters for the hub call
        # @option params [Evidence] :evidence The evidence object requiring verification
        # @option params [String] :action_name The administrative action being performed
        # @option params [String] :update_reason Reason for requesting verification
        # @option params [String] :updated_by Identifier of the user initiating the request
        #
        # @return [Dry::Monads::Success<String>] Success message if all steps complete
        # @return [Dry::Monads::Failure<String>] Error message if any step fails
        #
        # @example Successful hub call
        #   params = {
        #     evidence: income_evidence,
        #     action_name: "verify_income",
        #     update_reason: "Admin requested verification",
        #     updated_by: "admin@example.com"
        #   }
        #   result = call(params)
        #   # => Success("Event published successfully")
        def call(params)
          evidence, action_name, update_reason, updated_by = yield validate(params)
          application = yield fetch_application(evidence)
          yield is_application_valid?(application)
          record_history(evidence, action_name, update_reason, updated_by)
          payload_entity = yield build_and_validate_payload_entity(application, evidence)
          yield handle_successful_request(evidence, application)
          event_result = yield build_event(payload_entity.to_h)
          publish_result = yield publish_event_result(event_result)

          Success(publish_result)
        end

        # Determines and updates the eligibility state based on evidence status
        #
        # @example
        #   determine_eligibility_state(income_evidence)
        #   # Updates eligibility state based on current evidence state
        def determine_eligibility_state(evidence)
          eligibility = evidence.eligibility
          reason = "Hub response received for income evidence with state: #{evidence.current_state}, updated eligibility based on four evidences"
          eligibility.determine_eligibility_state(reason)
        end

        # Validates input parameters for hub call operations
        #
        # @example Successful validation
        #   params = {
        #     evidence: income_evidence,
        #     action_name: "verify_income",
        #     update_reason: "Admin requested verification",
        #     updated_by: "admin@example.com"
        #   }
        #   result = validate(params)
        #   # => Success([evidence, "verify_income", "Admin requested verification", "admin@example.com"])
        #
        def validate(params)
          required_keys = %i[evidence action_name update_reason updated_by]
          missing_keys = required_keys.reject { |key| params[key].present? }
          return Failure("Missing required params: #{missing_keys.join(', ')}") if missing_keys.any?

          Success([params[:evidence], params[:action_name], params[:update_reason], params[:updated_by]])
        end

        # Retrieves the application associated with the evidence
        #
        # Navigates through the evidence -> eligibility -> eligible -> application chain
        # to retrieve the financial assistance application for processing.
        def fetch_application(evidence)
          application = evidence.eligibility.eligible.application
          return Success(application) if application

          Failure("Application not found")
        end

        # Validates the application object
        def is_application_valid?(application)
          return Success(true) if application.valid?

          Failure("Application is invalid: #{application.errors.full_messages.join(', ')}")
        end

        # Builds and validates the application payload entity for communication
        #
        # Transforms the application data into the required payload format for
        # external hub communication and validates the structure against schemas.
        #
        # @param application [Application] The application to transform
        # @return [Dry::Monads::Success<PayloadEntity>] Valid payload entity for hub
        # @return [Dry::Monads::Failure<String>] Validation errors or transformation failures
        #
        # @see Operations::Fdsh::BuildAndValidateApplicationPayload
        # @example
        #   result = build_application_payload_entity(application)
        #   # => Success(#<PayloadEntity>)
        def build_application_payload_entity(application)
          ::Operations::Fdsh::BuildAndValidateApplicationPayload.new.call(application)
        end

        # Checks eligibility rules for applicants
        #
        # Validates that applicants meet the eligibility requirements for the
        # specified request type (e.g., income, esi, mec). This ensures only
        # eligible applicants are sent for verification.
        #
        # @param applicant_entity [ApplicantEntity] The applicant entity to check
        # @param request_type [Symbol] The type of verification request (:income, :esi, :mec)
        # @return [Dry::Monads::Success<Boolean>] True if applicant is eligible
        # @return [Dry::Monads::Failure<Array<String>>] Array of eligibility failure reasons
        #
        # @see Operations::Fdsh::PayloadEligibility::CheckApplicantEligibilityRules
        # @example
        #   result = check_eligibility_rules(applicant_entity, :income)
        #   # => Success(true) or Failure(["SSN required for income verification"])
        def check_eligibility_rules(applicant_entity, request_type)
          ::Operations::Fdsh::PayloadEligibility::CheckApplicantEligibilityRules.new.call(applicant_entity, request_type)
        end

        # Publishes event result and handles publication status
        #
        # Attempts to publish the verification event to the message queue and
        # returns appropriate success or failure status based on the result.
        def publish_event_result(event_result)
          event_result.publish ? Success("Event published successfully") : Failure("Event failed to publish")
        end

        # Handles successful request for determination
        #
        # Updates the evidence state to pending, determines eligibility state,
        # and saves the application after a successful hub verification request.
        # This marks the evidence as awaiting a response from the hub.
        #
        # @param evidence [Evidence] The evidence object to update
        # @param application [Application] The application to save
        # @return [Dry::Monads::Success<Boolean>] True if successfully processed
        #
        # @example
        #   result = handle_successful_request(income_evidence, application)
        #   # Evidence state changes to 'pending'
        #   # Eligibility state is updated
        #   # Application is saved to database
        def handle_successful_request(evidence, application)
          evidence.move_to_pending
          determine_eligibility_state(evidence)
          application.save!
          Success(true)
        end

        # Handles errors during request for determination
        #
        # Logs the error with full backtrace, records failure history for audit trail,
        # and returns a failure result when hub verification requests encounter errors.
        #
        # @param evidence [Evidence] The evidence object being processed
        # @param error [StandardError] The error that occurred during processing
        # @return [Dry::Monads::Failure<Boolean>] False indicating failure
        #
        # @example
        #   begin
        #     # hub call logic that might fail
        #   rescue StandardError => e
        #     result = handle_request_error(evidence, e)
        #     # Logs error, records history, returns Failure(false)
        #   end
        def handle_request_error(evidence, error)
          error_message = "Error requesting determination for #{evidence.key} evidence: #{error.message}"
          Rails.logger.error("#{error_message}, backtrace: #{error.backtrace.join("\n")}")

          record_history(evidence, 'Hub Request Failed', 'Error requesting determination', 'system')
          Failure(false)
        end

        # Records the history of evidence verification actions
        #
        # Creates a verification history record for tracking evidence state changes
        # and administrative actions performed on the evidence. This provides an
        # audit trail for all evidence modifications.
        #
        # @param evidence [Evidence] The evidence object to record history for
        # @param action_name [String] The action performed (e.g., 'Hub Request Failed', 'Verified')
        # @param update_reason [String] The reason for the update or action
        # @param updated_by [String] The identifier of the user or system performing the action
        # @return [void]
        #
        # @example Recording successful verification
        #   record_history(
        #     income_evidence,
        #     'Hub Request Successful',
        #     'Income verification completed',
        #     'system'
        #   )
        #
        # @example Recording manual override
        #   record_history(
        #     income_evidence,
        #     'Manual Override',
        #     'Admin approved based on submitted documents',
        #     'admin@example.com'
        #   )
        def record_history(evidence, action_name, update_reason, updated_by)
          evidence.build_verification_history(action_name, update_reason, updated_by)
        end

        # Handles failed hub verification requests
        #
        # Records failure history, updates eligibility state, saves the application,
        # and returns a failure result when hub verification requests fail due to
        # validation errors, eligibility issues, or processing failures.
        #
        # @param evidence [Evidence] The evidence object being processed
        # @param application [Application] The application to save
        # @param failure_reason [String] The detailed reason for the failure
        # @return [Dry::Monads::Failure<Boolean>] False indicating failure
        #
        # @example Validation failure
        #   failure_reason = "Income verification failed: SSN mismatch"
        #   result = handle_failed_request(evidence, application, failure_reason)
        #   # Records history, updates eligibility, saves application
        #
        # @example Eligibility failure
        #   failure_reason = "Applicant not eligible: Missing required information"
        #   result = handle_failed_request(evidence, application, failure_reason)
        def handle_failed_request(evidence, application, failure_reason)
          record_history(evidence, 'Hub Request Failed', failure_reason, 'system')
          determine_eligibility_state(evidence)
          application.save!
          Failure(false)
        end
      end
    end
  end
end
