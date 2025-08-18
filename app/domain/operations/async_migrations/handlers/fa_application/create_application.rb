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
            yield check_if_application_is_eligible_for_migration(application)
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

          def check_if_application_is_eligible_for_migration(application)
            family = application.family
            existing_app = ::FinancialAssistance::Application.where(family_id: family.id, assistance_year: application.assistance_year, aasm_state: "determined", origin: :migration, generation_reason: :manual)
            return Failure("Application hbx id: #{application.hbx_id} with family id: #{application.family_id} is not eligible for migration") if existing_app.present?

            Success(true)
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
            deactivate_tax_household_groups(determined_application)
            create_new_thhg(determined_application)
            family.save!
            ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
          end

          # Deactivates all existing tax household groups for the application's assistance year
          #
          # @param application [IndividualMarket::Application] the individual market application
          # @param family [Family] the family associated with the application
          # @return [Dry::Monads::Result] Success with message
          def deactivate_tax_household_groups(application)
            family = application.family
            new_effective_date = application.eligibility_determinations.pluck(:effective_starting_on).compact.first

            family.tax_household_groups.by_year(application.assistance_year).each do |thhg|
              thhg.end_on = new_effective_date > thhg.start_on ? (new_effective_date - 1.day) : thhg.start_on

              thhg.tax_households.each do |thh|
                thh.effective_ending_on = new_effective_date > thh.effective_starting_on ? (new_effective_date - 1.day) : thh.effective_starting_on
              end
            end
          end

          def create_new_thhg(application)
            family = application.family

            thhg_params = fetch_tax_hh_group_params(application)
            thhg = family.tax_household_groups.build(thhg_params)

            application.eligibility_determinations.each do |elig_deter|
              thh_params = fetch_tax_hh_params(elig_deter, application)
              thh = thhg.tax_households.build(thh_params)

              elig_deter.applicants.each do |applicant|
                thhm_params = fetch_thhm_params(applicant)
                thh.tax_household_members.build(thhm_params)
              end
            end
          end

          def fetch_tax_hh_group_params(application)
            { source: 'Faa',
              application_hbx_id: application.hbx_id,
              start_on: application.eligibility_determinations.first.effective_starting_on,
              end_on: nil,
              assistance_year: application.assistance_year }
          end

          def fetch_tax_hh_params(elig_deter, application)
            { eligibility_determination_hbx_id: elig_deter.hbx_assigned_id,
              yearly_expected_contribution: elig_deter.yearly_expected_contribution,
              effective_starting_on: elig_deter.effective_starting_on || application.effective_date,
              max_aptc: elig_deter.max_aptc }
          end

          def fetch_thhm_params(applicant)
            { applicant_id: applicant.family_member_id,
              medicaid_household_size: applicant.medicaid_household_size,
              magi_medicaid_category: applicant.magi_medicaid_category,
              magi_as_percentage_of_fpl: applicant.magi_as_percentage_of_fpl,
              magi_medicaid_monthly_income_limit: applicant.magi_medicaid_monthly_income_limit,
              magi_medicaid_monthly_household_income: applicant.magi_medicaid_monthly_household_income,
              is_without_assistance: applicant.is_without_assistance,
              is_ia_eligible: applicant.is_ia_eligible,
              is_medicaid_chip_eligible: applicant.is_medicaid_chip_eligible,
              is_non_magi_medicaid_eligible: applicant.is_non_magi_medicaid_eligible,
              is_totally_ineligible: applicant.is_totally_ineligible,
              is_csr_eligible: applicant.is_csr_eligible,
              csr_percent_as_integer: applicant.csr_percent_as_integer,
              member_determinations: member_determinations(applicant)}
          end

          def member_determinations(applicant)
            applicant.member_determinations&.map do |member_determination|
              md_attributes = member_determination.attributes
              md_attributes.except!('_id', 'created_at', 'updated_at')
              eo_attributes = member_determination.eligibility_overrides&.map do |eo|
                eo.attributes.except!('_id', 'created_at', 'updated_at')
              end
              md_attributes['eligibility_overrides'] = eo_attributes
              md_attributes
            end
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
            application_compact_result = [application.family_id, application.hbx_id, application.primary_applicant.person_hbx_id, "migrated"]
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
                status = [application.family_id, application.hbx_id, "migrated", "", applicant.person_hbx_id]
                compare_aptc_csr_eligibility_evidences(old_evidence, new_evidence, status)
                application_result << status
              end
            end

            individual_market_evidences_result = Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::CompareMigratedEvidenceValues.new.call(application: application)

            if individual_market_evidences_result.success?
              individual_market_evidences_result.value!.each do |result|
                application_result.push(result)
              end

              Success(fetch_compact_result(application_result, application_compact_result))
            else
              Failure("Failed to compare migrated values")
            end
          end

          def fetch_compact_result(application_result, application_compact_result)
            result = application_result.collect do |matched|
              matched[6] == true && matched[8] == true && matched[10] == true && matched[12] == true && matched[14] == true
            end

            if result.all? { |value| value == true }
              application_compact_result.push("All evidences matched successfully")
            else
              application_compact_result.push("Some evidences did not match")
            end
            application_compact_result
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

              if documents_matched?(old_evidence, new_evidence)
                status.push("#{new_evidence.key}_document", true)
              else
                status.push("#{new_evidence.key}_document", false)
              end

            else
              status.push(new_evidence.key.to_s, false)
            end
          end

          def documents_matched?(old_evidence, new_evidence)
            old_evidence.documents.count == new_evidence.documents.count &&
              old_evidence.documents.all? do |old_doc|
                new_evidence.documents.any? do |new_doc|
                  old_doc.title == new_doc.title &&
                    old_doc.subject == new_doc.subject &&
                    old_doc.description == new_doc.description
                end
              end
          end

          def attributes_match?(obj1, obj2, attributes)
            obj1.as_json(only: attributes) == obj2.as_json(only: attributes)
          end

          def publish(row)
            csv_headers = [
                           "Family ID",
                           "Application HBX ID",
                           "Primary Applicant HBX ID",
                           "Migration Result",
                           "Errors"
                          ]

            # result = rows.collect do |row|
            event = event("events.migration_results.enqueue_result", attributes: {csv_file_name: "new_fa_application_report", csv_headers: csv_headers, csv_row: row})

            result = if event.success?
                       event.success.publish
                       true
                     else
                       false
                     end

            result ? Success("New FA Application created successfully and published to migration results") : Failure("New FA Application created successfully and publish failed")
          end
        end
      end
    end
  end
end
