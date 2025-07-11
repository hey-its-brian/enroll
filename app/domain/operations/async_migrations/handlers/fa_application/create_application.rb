# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module FAApplication
        # Handles the creation and migration of financial assistance applications
        #
        # This class is responsible for creating new financial assistance applications
        # by copying existing applications and generating appropriate eligibilities
        # and evidences
        #
        # @api public
        #
        # @example Create a new application from existing one
        #   handler = CreateApplication.new
        #   result = handler.call(document_id: existing_application_id)
        #
        #   if result.success?
        #     puts "Application created: #{result.success.hbx_id}"
        #   else
        #     puts "Creation failed: #{result.failure}"
        #   end
        class CreateApplication
          include Dry::Monads[:do, :result]
          include EventSource::Command
          include ::ResourceRegistryHelper

          def call(params)
            application_id = yield validate(params)
            application = yield find_application(application_id)
            draft_application = yield generate_new_draft_application(application)
            yield generate_eligibilities(draft_application, application)
            determined_application = yield move_to_determined(draft_application, application)
            yield regenerate_family_determination(determined_application)
            yield cancel_previous_applications(draft_application)
            comparison_result = yield compare_migrated_values(determined_application, application)
            yield publish(comparison_result)
            Success(["New application created for family: #{determined_application.family_id} with new_application_hbx_id:", determined_application.hbx_id])
          end

          private

          # Validates the input parameters.
          #
          # @param params [Hash] The input parameters to validate.
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure]
          #   A success monad with the document ID if validation passes, or a failure monad with an error message.
          def validate(params)
            return Failure("qhp_application_feature flag is not enabled") unless qhp_application_feature_enabled?
            return Failure("Params must be a hash") unless params.is_a?(Hash)
            return Failure("Document id must be of valid BSON::ObjectId format") unless BSON::ObjectId.legal?(params[:document_id])

            Success(params[:document_id])
          end

          # Finds the financial assistance application by its ID.
          #
          # @param application_id [String] The BSON ObjectId of the application.
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure]
          def find_application(application_id)
            application = ::FinancialAssistance::Application.where(id: application_id).first
            application ? Success(application) : Failure('Application not found')
          end

          def generate_new_draft_application(application)
            copy_result = ::Operations::AsyncMigrations::Handlers::FAApplication::CopyWithoutPersisting.new.call(
              {
                application_id: application.id,
                origin: :migration,
                generation_reason: :manual
              }
            )

            copy_result.success? ? Success(copy_result.value!) : Failure("Failed to copy application: #{copy_result.failure}")
          end

          # @note This method:
          #   * Generates individual market eligibilities and evidences for each applicant
          #   * Migrates APTC/CSR eligibility data from old to new applicants
          #   * Copies evidence records with appropriate type mapping
          #   * Builds new evidences for each applicant
          def generate_eligibilities(draft_application, application)
            migrator = ::Migrations::DataModelMigrator.new
            draft_application.applicants.each do |new_applicant|
              old_applicant = application.applicants.select { |app| app.person_hbx_id == new_applicant.person_hbx_id }.first

              person = Person.where(hbx_id: old_applicant.person_hbx_id).first
              consumer_role = person.consumer_role
              new_applicant.assign_attributes(
                age_off_excluded: person.age_off_excluded,
                contact_method: consumer_role.contact_method,
                language_preference: consumer_role.language_preference
              )

              # Build individual_market_eligibility and its evidences
              # social security number verification type ---> social security number evidence
              # citizenship verification type ---> citizenship evidence
              result = Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::GenerateEvidences.new.call(applicant: new_applicant)
              return Failure("Failed while generating applicant #{new_applicant.person_hbx_id} evidences #{result.failure}") if result.failure?

              # Migrate existing aptc csr eligibility evidences
              old_aptc_csr_eligibility = old_applicant.aptc_csr_eligibility
              raise "No APTC/CSR eligibility object found for old applicant #{old_applicant.person_hbx_id}" unless old_aptc_csr_eligibility
              new_aptc_csr_eligibility = new_applicant.build_aptc_csr_eligibility
              migrator.perform(old_aptc_csr_eligibility, new_aptc_csr_eligibility)
              old_aptc_csr_eligibility.evidences.each do |old_evidence|
                new_evidence = build_new_evidence(new_aptc_csr_eligibility, old_evidence)
                migrator.perform(old_evidence, new_evidence)
                new_evidence.due_date_extended_at = fetch_date_from_verification_histories(new_evidence.verification_histories) if new_evidence.key.to_s == "income_evidence"
              end
            end

            Success(draft_application)
          rescue StandardError => e
            Failure("generation failed for the application: #{application.hbx_id} with error: #{e.message}")
          end

          def fetch_date_from_verification_histories(verification_histories)
            return nil if verification_histories.blank?
            verification_histories.where(:action.in => ["auto_extend_due_date", "manually_extend_due_date"]).order_by(:date_of_action.desc).first&.date_of_action
          end

          def build_new_evidence(aptc_csr_eligibility, old_evidence)
            aptc_csr_eligibility.evidences.build(
              _type: old_evidence._type,
              title: old_evidence.title,
              key: old_evidence.key
            )
          end

          def move_to_determined(draft_application, application)
            draft_application.assign_attributes(assistance_year: application.assistance_year, aasm_state: "determined", origin: :migration, generation_reason: :manual, submitted_at: Time.current)
            draft_application.workflow_state_transitions.build(
              event: 'determine',
              from_state: 'draft',
              to_state: 'determined',
              transition_at: Time.current,
              reason: "migrating from the latest determined application #{application.hbx_id} to create individual_market eligibilities"
            )

            draft_application.save!
            Success(draft_application)
          rescue StandardError => e
            Failure("Failed to move to determined: #{e.message}")
          end

          def regenerate_family_determination(determined_application)
            family = determined_application.family
            family.assign_latest_application_gid
            ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
          end

          # Cancels previous draft applications when a new one is created
          # @param [FinancialAssistance::Application] draft_app The newly created draft application
          # @return [Dry::Monads::Result::Success] Success monad with a message
          def cancel_previous_applications(draft_app)
            if qhp_application_feature_enabled?
              ::Operations::Sbm::Applications::CancelPreviousApplications.new.call(
                application: draft_app
              )
              Success('Previous applications cancelled successfully')
            else
              # Returns success as we don't want to modify the application creation result
              # when the feature flag is disabled
              Success('Cannot cancel applications as feature flag is disabled')
            end
          end

          def compare_migrated_values(application, old_application)
            application_result = []
            application.applicants.each do |applicant|
              old_aptc_csr_eligibility = old_application.applicants.where(person_hbx_id: applicant.person_hbx_id).first.aptc_csr_eligibility
              old_income_evidence = old_aptc_csr_eligibility.income_evidence
              old_esi_evidence = old_aptc_csr_eligibility.esi_mec_evidence
              old_local_mec_evidence = old_aptc_csr_eligibility.local_mec_evidence
              old_non_esi_evidence = old_aptc_csr_eligibility.non_esi_mec_evidence

              aptc_csr_eligibility = applicant.aptc_csr_eligibility
              new_income_evidence = aptc_csr_eligibility.income_evidence
              new_esi_evidence = aptc_csr_eligibility.esi_mec_evidence
              new_local_mec_evidence = aptc_csr_eligibility.local_mec_evidence
              new_non_esi_evidence = aptc_csr_eligibility.non_esi_mec_evidence

              [[old_income_evidence, new_income_evidence], [old_esi_evidence, new_esi_evidence], [old_local_mec_evidence, new_local_mec_evidence], [old_non_esi_evidence, new_non_esi_evidence]].each do |old_evidence, new_evidence|
                next unless old_evidence.present?
                status = [application.hbx_id, "migrated", "", applicant.person_hbx_id]
                compare_aptc_csr_eligibility_evidences(old_evidence, new_evidence, status)
                application_result << status
              end
            end

            individual_market_evidences_result = Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::CompareMigratedEvidenceValues.new.call(application: application)

            if individual_market_evidences_result.success?
              individual_market_evidences_result.value!.each do |result|
                application_result.push(result)
              end
              Success(application_result)
            else
              Failure("Failed to compare migrated values")
            end
          end

          def compare_aptc_csr_eligibility_evidences(old_evidence, new_evidence, status)
            if new_evidence.present?
              evidence_attributes = ["key", "current_state", "verification_outstanding", "due_on", "updated_by", "external_service", "title", "description", "is_satisfied", "determined_at", "is_active"]
              if attributes_match?(old_evidence, new_evidence, evidence_attributes)
                status.push(new_evidence.key.to_s, true)
              else
                status.push(new_evidence.key.to_s, false)
              end

              verification_history_attributes = ["action", "updated_by", "update_reason", "is_satisfied", "verification_outstanding", "due_on", "date_of_action"]
              if attributes_match?(old_evidence.verification_histories.first, new_evidence.verification_histories.first, verification_history_attributes)
                status.push("#{new_evidence.key}_verification_history", true)
              elsif old_evidence.verification_histories.first
                status.push("#{new_evidence.key}_verification_history", false)
              end

              request_result_attributes = ["result", "source_transaction_id", "source", "code", "code_description", "raw_payload", "action"]
              status.push("#{new_evidence.key}_request_result", true) if attributes_match?(old_evidence.request_results.first, new_evidence.request_results.first, request_result_attributes)

              state_history_attributes = ["effective_on", "is_eligible", "metadata", "from_state", "to_state", "transition_at", "event", "comment", "reason"]
              if attributes_match?(old_evidence.state_histories.first, new_evidence.state_histories.first, state_history_attributes)
                status.push("#{new_evidence.key}_state_history", true)
              elsif old_evidence.state_histories.first
                status.push("#{new_evidence.key}_state_history", false)
              end

            else
              status.push(new_evidence.key.to_s, false)
            end
          end

          def attributes_match?(obj1, obj2, attributes)
            obj1.as_json(only: attributes) == obj2.as_json(only: attributes)
          end

          def publish(rows)
            csv_headers = ["Application HBX ID",
                           "Migration Result",
                           "Errors",
                           "Applicant HBX ID",
                           "evidence_type",
                           "evidence_values_matched?",
                           "evidence_verification_history",
                           "evidence_verification_histories_matched?",
                           "evidence_request_result",
                           "evidence_request_results_matched?",
                           "evidence_state_transition",
                           "evidence_state_transitions_matched?",
                           "evidence_document_type",
                           "evidence_document_matched?"]

            result = rows.collect do |row|
              event = event("events.migration_results.enqueue_result", attributes: {csv_file_name: "new_fa_application_report", csv_headers: csv_headers, csv_row: row})

              if event.success?
                event.success.publish
              else
                false
              end
            end

            result.all?(true) ? Success("All evidence migration events published successfully") : Failure("Some evidence migration events failed to publish")
          end
        end
      end
    end
  end
end
