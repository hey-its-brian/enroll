# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module FinancialAssistance
  module Operations
    module Applications
      module Shared
        # Shared functionality for Non ESI Evidence request operations (RRV and PVC)
        # This module contains common logic for processing Non ESI evidence requests
        module NonEsiEvidenceRequest
          include Dry::Monads[:do, :result]
          include EventSource::Command
          include EventSource::Logging

          def call(params)
            values = yield validate(params)
            application = yield fetch_application(values)
            _success = yield build_evidence_history(application, submitted_action, submitted_message, 'system')
            cv3_application = yield transform_and_validate_application(application)
            _saved = yield save_application(application)
            event = yield build_event(cv3_application)
            publish(event)

            Success(success_message(params[:application_hbx_id]))
          end

          private

          def validate(params)
            errors = params[:application_hbx_id].present? ? [] : ['application hbx_id is missing']
            errors.empty? ? Success(params) : handle_validation_failure(errors)
          end

          def fetch_application(params)
            application = ::FinancialAssistance::Application.by_hbx_id(params[:application_hbx_id]).first
            if application.present?
              application.valid? ? Success(application) : Failure("Invalid application: #{params[:application_hbx_id]}")
            else
              logger.error("No application found with hbx_id #{params[:application_hbx_id]}")
              Failure("No application found with hbx_id #{params[:application_hbx_id]}")
            end
          end

          def transform_and_validate_application(application)
            payload_entity = build_and_validate_payload(application)

            if payload_entity.success?
              all_applicants_valid = validate_applicants(payload_entity, application)
              move_applicant_eligibility_state(application)
              save_application(application)
              return payload_entity if all_applicants_valid.any?(&:last)
              return Failure("Failed to transform application with hbx_id #{application.hbx_id} due to all applicants are invalid")
            elsif payload_entity.failure?
              move_applicant_eligibility_state(application)
              record_application_failure(application, payload_entity.failure.messages)
              save_application(application)
            end

            payload_entity
          rescue StandardError => e
            logger.error("#{process_name} process failed to publish event for the application with hbx_id #{application.hbx_id} due to #{e.inspect}")
            Failure("#{process_name} process failed to publish event for the application with hbx_id #{application.hbx_id} due to #{e.inspect}")
          end

          def move_applicant_eligibility_state(application)
            reason = eligibility_state_reason
            application.active_applicants.each do |applicant|
              applicant.aptc_csr_eligibility.determine_eligibility_state(reason)
            end
          end

          def validate_applicants(payload_entity, application)
            eligible_applicants = applicants_with_evidence(application)
            applicants_entity = payload_entity.value!.applicants

            eligible_applicants.map do |eligible_applicant|
              applicant_entity = find_matching_applicant_entity(eligible_applicant, applicants_entity)
              result = check_applicant_eligibility_rules(applicant_entity)

              if result.success?
                [applicant_entity.person_hbx_id, true]
              else
                record_applicant_failure(non_esi_evidence_for(eligible_applicant), result)
                [applicant_entity.person_hbx_id, false]
              end
            end
          end

          def record_applicant_failure(evidence, result)
            build_verification_history(evidence, submission_failed_action, submission_failed_message(result.failure), 'system')
            assign_evidence_to_default_state(evidence)
          end

          def record_application_failure(application, error_messages)
            build_evidence_history(application, submission_failed_action, submission_failed_message(error_messages), 'system')
            assign_evidence_state_for_all_applicants(application)
          end

          def build_evidence_history(application, action, update_reason, update_by)
            with_evidences(application) do |evidence|
              build_verification_history(evidence, action, update_reason, update_by)
            end
            Success(true)
          end

          def assign_evidence_state_for_all_applicants(application)
            with_evidences(application) do |evidence|
              assign_evidence_to_default_state(evidence)
            end
          end

          # Helper methods to reduce repetition and improve readability

          # Extract non-ESI evidence for a given applicant
          def non_esi_evidence_for(applicant)
            applicant&.aptc_csr_eligibility&.non_esi_mec_evidence
          end

          # Get applicants that have non-ESI evidence
          def applicants_with_evidence(application)
            application.active_applicants.select { |app| non_esi_evidence_for(app).present? }
          end

          # Iterate over all active applicants
          def with_eligible_applicants(application, &block)
            application.active_applicants.each(&block)
          end

          # Iterate over evidences for applicants that have them
          def with_evidences(application)
            application.active_applicants.each do |applicant|
              evidence = non_esi_evidence_for(applicant)
              next unless evidence.present?
              yield(evidence)
            end
          end

          # Find matching applicant entity by person_hbx_id
          def find_matching_applicant_entity(eligible_applicant, applicants_entity)
            applicants_entity.detect { |appl_entity| eligible_applicant.person_hbx_id == appl_entity.person_hbx_id }
          end

          def build_verification_history(evidence, action, update_reason, update_by)
            evidence.build_verification_history(action, update_reason, update_by) if evidence.present?
          end

          # update non esi evidence state to default state for applicant
          def assign_evidence_to_default_state(evidence)
            evidence&.mark_as_attested
          end

          def save_application(application)
            if application.save
              Success(application)
            else
              error_msg = "Failed to save application: #{application.errors.full_messages.join(', ')}"
              logger.error(error_msg)
              Failure(error_msg)
            end
          end

          def publish(event)
            event.publish
            Success(publish_success_message)
          end

          # Abstract methods that must be implemented by including classes

          def success_message(_application_hbx_id)
            raise NotImplementedError, "#{self.class} must implement #success_message"
          end

          def submitted_action
            raise NotImplementedError, "#{self.class} must implement #submitted_action"
          end

          def submitted_message
            raise NotImplementedError, "#{self.class} must implement #submitted_message"
          end

          def submission_failed_action
            raise NotImplementedError, "#{self.class} must implement #submission_failed_action"
          end

          def submission_failed_message(_error)
            raise NotImplementedError, "#{self.class} must implement #submission_failed_message"
          end

          def eligibility_state_reason
            raise NotImplementedError, "#{self.class} must implement #eligibility_state_reason"
          end

          def process_name
            raise NotImplementedError, "#{self.class} must implement #process_name"
          end

          def build_event(_cv3_application)
            raise NotImplementedError, "#{self.class} must implement #build_event"
          end

          def logger
            raise NotImplementedError, "#{self.class} must implement #logger"
          end

          def publish_success_message
            raise NotImplementedError, "#{self.class} must implement #publish_success_message"
          end

          def build_and_validate_payload(_application)
            raise NotImplementedError, "#{self.class} must implement #build_and_validate_payload"
          end

          def check_applicant_eligibility_rules(_applicant_entity)
            raise NotImplementedError, "#{self.class} must implement #check_applicant_eligibility_rules"
          end

          def handle_validation_failure(_errors)
            raise NotImplementedError, "#{self.class} must implement #handle_validation_failure"
          end
        end
      end
    end
  end
end
