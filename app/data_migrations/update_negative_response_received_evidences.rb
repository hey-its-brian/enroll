# frozen_string_literal: true

require File.join(Rails.root, "lib/mongoid_migration_task")

# This migration updates the verification_outstanding and is_satisfied fields for evidences
# that are in the negative_response_received state and have verification_outstanding set to true.
# It sets verification_outstanding to false, is_satisfied to true, and due_on to nil.
# The migration processes applications in batches to minimize memory usage.
#
# Usage:
# RAILS_ENV=production bundle exec rake migrations:update_negative_response_received_evidences
class UpdateNegativeResponseReceivedEvidences < MongoidMigrationTask
  def migrate
    logger = Rails.logger.tagged("update_negative_response_received_evidences")
    logger.info "Starting migration to update negative response received evidences"

    count = 0

    applications = FinancialAssistance::Application.determined.where(
      "$or" => evidence_query_conditions
    )

    logger.info "Found #{applications.count} applications to process"

    applications.each do |application|
      process_application(application, logger)
      count += 1
    rescue StandardError => e
      logger.error "Failed to process application #{application.id}: #{e.message}"
    end

    logger.info "Successfully processed #{count} applications"
  end

  private

  def evidence_query_conditions
    FinancialAssistance::Applicant::EVIDENCES.map do |evidence|
      { "applicants" => { "$elemMatch" => {"#{evidence}.aasm_state" => "negative_response_received", "#{evidence}.verification_outstanding" => true} } }
    end
  end

  def process_application(application, logger)
    updated_count = 0

    application.applicants.each do |applicant|
      FinancialAssistance::Applicant::EVIDENCES.each do |evidence_type|
        evidence = applicant.send(evidence_type)
        next unless evidence && evidence.aasm_state == "negative_response_received" && evidence.verification_outstanding

        if evidence.update(verification_outstanding: false, is_satisfied: true, due_on: nil)
          updated_count += 1
        else
          logger.warn "Failed to update evidence #{evidence_type} for applicant #{applicant.person_hbx_id}"
        end
      end
    end

    logger.info "Updated #{updated_count} evidences for application #{application.id}"
  end
end
