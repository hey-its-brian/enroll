# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module FAApplication
        # Handles the migration of evidence for financial assistance applications.
        #
        # This class validates input parameters, finds the application, and migrates evidence
        # from the old model to the new model using the `migrate_to_new_model` method.
        class MigrateEvidence
          include Dry::Monads[:do, :result]
          include EventSource::Command
          include ::ResourceRegistryHelper

          EVIDENCE_TYPE_MAPPING = {
            income: 'FinancialAssistance::Evidences::IncomeEvidence',
            esi_mec: 'FinancialAssistance::Evidences::EsiMecEvidence',
            local_mec: 'FinancialAssistance::Evidences::LocalMecEvidence',
            non_esi_mec: 'FinancialAssistance::Evidences::NonEsiMecEvidence'
          }.freeze

          EVIDENCE_TITLE_MAPPING = {
            income: 'Income Evidence',
            esi_mec: 'ESI MEC Evidence',
            local_mec: 'Local MEC Evidence',
            non_esi_mec: 'Non ESI MEC Evidence'
          }.freeze

          EVIDENCE_KEY_MAPPING = {
            income: :income_evidence,
            esi_mec: :esi_mec_evidence,
            local_mec: :local_mec_evidence,
            non_esi_mec: :non_esi_mec_evidence
          }.freeze

          # Executes the migration process.
          #
          # @param params [Hash] The input parameters containing the document ID.
          # @option params [String] :document_id The BSON ObjectId of the application document.
          # @return [Dry::Monads::Result] A success or failure monad indicating the result of the operation.
          def call(params)
            application_id = yield validate(params)
            application = yield find_application(application_id)
            yield check_if_application_is_eligible_for_migration?(application)
            result = yield migrate_evidence(application)
            comparison_result = yield compare_migrated_values(application, result)
            yield publish(comparison_result)

            Success(comparison_result)
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

          def check_if_application_is_eligible_for_migration?(application)
            result = application.applicants.any? { |applicant| applicant.aptc_csr_eligibility.present? }
            result ? Failure("Applicant with APTC/CSR eligibility found, application hbx id: #{application.hbx_id} is not eligible for migration") : Success("No applicant with APTC/CSR eligibility found")
          end

          # Migrates evidence for all applicants in the application.
          #
          # This method iterates through each applicant and their evidences, migrating them
          # from the old model to the new model using the `migrate_to_new_model` method.
          #
          # @param application [FinancialAssistance::Application] The application containing applicants and evidences.
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure]
          #   A success monad if the migration completes successfully, or a failure monad with an error message.
          def migrate_evidence(application)
            app_hbx_id = application.hbx_id
            return Success([app_hbx_id, application.aasm_state,"not eligible for migration", application.errors.full_messages.join(", ")]) unless application.valid?

            migration_status = []
            application.applicants.each do |applicant|
              aptc_csr_eligibility = applicant.build_aptc_csr_eligibility
              evidences_result = build_and_migrate_evidences(aptc_csr_eligibility, applicant)
              if evidences_result.compact.flatten.blank?
                migration_status << false
                next
              end

              assign_attributes_to_aptc_csr_eligibility(aptc_csr_eligibility, evidences_result, application)
              migration_status << true
            end
            # @note This section addresses the issue of multiple database saves caused by `aptc_csr_eligibility.save!` for each applicant.
            #   - Saving the `application` also saves its embedded documents (e.g., `aptc_csr_eligibility`) and triggers callbacks in the `Applicant` model.
            #   - However, saving `aptc_csr_eligibility` does not save the parent document (`application`) and does not trigger any callbacks.
            #   - To optimize performance and avoid redundant saves, callbacks on the `Applicant` and `Relationship` models are temporarily skipped during the migration process.

            migration_result = if migration_status.any?(true) && application.valid?
                                 application.save!
                                 [app_hbx_id, application.aasm_state, "migrated",""]
                               elsif migration_status.all?(false)
                                 [app_hbx_id, application.aasm_state, "no evidences found", ""]
                               else
                                 [app_hbx_id, application.aasm_state,"not migrated", application.errors.full_messages.join(", ")]
                               end

            Success(migration_result)
          rescue StandardError => e
            Failure("Evidence migration failed for application hbx_id: #{application.hbx_id}, errors: #{e.message}")
          end

          def assign_attributes_to_aptc_csr_eligibility(aptc_csr_eligibility, evidences_result, application)
            aptc_csr_eligibility_current_state = determine_eligibility_state(evidences_result, application)
            aptc_csr_eligibility_is_satisfied = evidences_result.all?{ |array|  array[1] == true}
            if aptc_csr_eligibility_current_state == :move_to_initial
              aptc_csr_eligibility.assign_attributes(is_satisfied: false, determined_at: nil, current_state: :initial)
            else
              reason = "migrating from the application #{application.hbx_id} to create aptc_csr_eligibility"
              case aptc_csr_eligibility_current_state
              when :satisfy
                aptc_csr_eligibility.satisfy(reason: reason)
              when :pend
                aptc_csr_eligibility.pend(reason: reason)
              when :verification_in_progress
                aptc_csr_eligibility.unsatisfy(reason: reason)
              end

              aptc_csr_eligibility.assign_attributes(is_satisfied: aptc_csr_eligibility_is_satisfied, determined_at: Time.now)
            end
          end

          # Determines the eligibility state based on evidence states and application draft status.
          #
          # @param evidence_states [Array<Array>] The states and satisfaction statuses of the evidences.
          # @param is_draft [Boolean] Whether the application is in draft state.
          # @return [Symbol] The determined eligibility state.
          def determine_eligibility_state(evidence_states, application)
            if application.draft?
              :move_to_initial
            elsif evidence_states.present? && evidence_states.all? { |state, _| %i[verified attested].include?(state) }
              :satisfy
            else
              :pend
            end
          end

          def build_and_migrate_evidences(aptc_csr_eligibility, applicant)
            ::FinancialAssistance::Applicant::EVIDENCES.filter_map.collect do |evidence_key|
              old_evidence = applicant.fetch_evidence(evidence_key.to_s)

              next if old_evidence.blank?
              new_evidence = build_new_evidence(aptc_csr_eligibility, old_evidence)
              evidence_migrator = ::Migrations::DataModelMigrator.new
              evidence_migrator.perform(old_evidence, new_evidence)
              new_evidence.determined_at = new_evidence.request_results.order_by(:date_of_action.desc).first&.date_of_action
              new_evidence.state_histories.each do |new_model_state_history|
                new_model_state_history.is_eligible = [:outstanding, :rejected].include?(new_model_state_history.to_state) ? false : true
                new_model_state_history.effective_on = new_model_state_history.transition_at
              end

              [new_evidence.current_state, new_evidence.is_satisfied]
            end.compact
          end

          def build_new_evidence(aptc_csr_eligibility, old_evidence)
            key = old_evidence.key.to_s
            evidence_title = EVIDENCE_TITLE_MAPPING[key.to_sym]
            evidence_type = EVIDENCE_TYPE_MAPPING[key.to_sym]
            evidence_key = EVIDENCE_KEY_MAPPING[key.to_sym]

            aptc_csr_eligibility.evidences.build(
              _type: evidence_type,
              title: evidence_title,
              key: evidence_key
            )
          end

          def compare_migrated_values(application, result)
            if result[2] == "migrated"
              Operations::AsyncMigrations::Handlers::FAApplication::CompareMigratedEvidenceValues.new.call(application: application)
            else
              Success(result)
            end
          end

          def publish(row)
            csv_headers = ["Application HBX ID",
                           "Application State",
                           "Migration Status",
                           "Migrated Evidence Result"]

            # result = rows.collect do |row|
            event = event("events.migration_results.enqueue_result", attributes: {csv_file_name: "migrated_evidences_1.0_to_3.0_report", csv_headers: csv_headers, csv_row: row})

            result = if event.success?
                       event.success.publish
                       true
                     else
                       false
                     end
            # end
            result ? Success("Evidence migration event published successfully") : Failure("Evidence migration event publishing failed")
          end
        end
      end
    end
  end
end