# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module IndividualMarketEligibility
        # This class is responsible for creating QHP applications.
        class CreateApplication
          include Dry::Monads[:do, :result]
          include EventSource::Command

          def call(params)
            family_id = yield validate(params)
            family = yield find_family(family_id)
            yield check_if_family_is_eligible_for_migration(family)
            application = yield transform_family(family)
            draft_application = yield build_application(application)
            result = yield submit_application(draft_application)
            applicants_result = yield determine_applicants(result)
            application_result = yield determine_application(applicants_result)
            yield deactivate_tax_household_groups(application_result)
            yield build_tax_household_group(application_result)
            yield regenerate_family_determination(application_result)
            comparison_result = yield compare_migrated_values(application_result)
            yield publish(comparison_result)

            Success(["completed request for family #{family_id}, check report for the status of the application creation", draft_application.hbx_id])
          end

          private

          def validate(params)
            return Failure('family_id is expected in BSON format') unless BSON::ObjectId.legal?(params[:document_id])

            Success(params[:document_id].to_s)
          end

          def find_family(family_id)
            family_find_result = ::Operations::Families::Find.new.call(id: BSON::ObjectId(family_id))
            return family_find_result if family_find_result.failure?

            Success(family_find_result.success)
          end

          def transform_family(family)
            contract_result = ::Validators::IndividualMarket::ApplicationContract.new.call(application_attributes(family))
            contract_result.success? ? Success(contract_result.to_h) : Failure(contract_result.errors)
          end

          def check_if_family_is_eligible_for_migration(family)
            assistance_year = family.application_applicable_year

            qhp_app = ::IndividualMarket::Application.newest_determined_by_family_id(family.id).only(
              :assistance_year, :current_state, :family_id, :id, :submitted_at
            ).first
            return Failure("Family with id: #{family.id} is not eligible for migration, QHP application exists") if qhp_app.present?

            any_determined_financial_assistance_applications = ::FinancialAssistance::Application.only(:id, :family_id, :assistance_year, :submitted_at, :aasm_state)
                                                                                                 .where(aasm_state: 'determined', family_id: family.id, assistance_year: assistance_year)
                                                                                                 .order_by(submitted_at: :desc)
                                                                                                 .group_by(&:assistance_year)

            return Failure("Family with id: #{family.id} is not eligible for migration, determined financial assistance applications exist for assistance year #{assistance_year}") if any_determined_financial_assistance_applications.present?

            any_valid_hbx_enrollments = HbxEnrollment.only(:family_id, :effective_on, :aasm_state)
                                                     .where(family_id: family.id,
                                                            effective_on: {'$gte' => Date.new(assistance_year), '$lte' => Date.new(assistance_year).end_of_year},
                                                            aasm_state: { '$in' => ['coverage_selected', 'coverage_canceled', 'coverage_terminated', 'auto_renewing', 'unverified']})

            return Failure("Family with id: #{family.id} is not eligible for migration, valid hbx enrollments does not exist") unless any_valid_hbx_enrollments.present?

            Success(true)
          end

          def application_attributes(family)
            application_attrs = {
              family_id: family.id,
              assistance_year: family.application_applicable_year,
              origin: :migration,
              generation_reason: :manual,
              submitted_at: DateTime.current,
              current_state: :initial
            }

            application_attrs.merge!({applicants: applicants_attributes(family)})
            application_attrs
          end

          def applicants_attributes(family)
            family.active_family_members.inject([]) do |members_array, family_member|
              member_attrs_result = ::Operations::IndividualMarket::ParseApplicant.new.call({family_member: family_member})
              members_array << member_attrs_result.success if member_attrs_result.success?
              members_array
            end
          end

          def build_application(application_params)
            application_params[:applicants].each { |a| a.delete(:eligibilities) }
            application = ::IndividualMarket::Application.new(application_params)
            application.applicants.map do |applicant|
              result = build_evidences(applicant)

              return Failure(result.failure) unless result.success?
            end

            build_relationships(application)
            Success(application)
          end

          # Builds evidence records for an applicant
          # @param eligibility [IndividualMarket::Eligibility] The eligibility to build evidences for
          # @param member [FamilyMember] The family member associated with the eligibility
          # @return [void]
          def build_evidences(applicant)
            Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::GenerateEvidences.new.call(applicant: applicant)
          end

          # Builds eligibility records for an applicant
          # @param applicant [IndividualMarket::Applicant] The applicant to build eligibilities for
          # @param eligibilities [Array<Hash>] Array of eligibility parameters
          # @option eligibilities [Symbol] :key The type of eligibility
          # @option eligibilities [String] :title The display title for the eligibility
          # @return [void]
          def build_eligibilities(applicant, eligibilities)
            eligibilities.each do |eligibility|
              eligibility_class = ELIGIBILITY_CLASSES[eligibility[:key]]
              next unless eligibility_class

              applicant.eligibilities.build(eligibility.merge(_type: eligibility_class))
            end
          end

          # Builds relationship records between primary applicant and dependents
          # @param application [IndividualMarket::Application] The application containing the applicants
          # @return [void]
          # @note Relationships are only built for non-primary applicants who have a defined relationship
          #   to the primary applicant through their family member record
          def build_relationships(application)
            primary_applicant = application.primary_applicant

            application.non_primary_applicants.each do |applicant|
              next unless applicant.family_member&.relationship

              relationships_params = {
                source_id: applicant.id,
                relative_id: primary_applicant.id,
                kind: applicant.family_member.relationship
              }

              application.relationships.build(relationships_params)
            end
          end

          def submit_application(application)
            application.attestation = ::IndividualMarket::Attestation.new(signer_role: "system", signer_id: nil, signed_at: nil)
            application.submit
            application.set_submit

            if application.valid?
              Success([application, true, "Application transitioned to submitted successfully but not persisted"])
            else
              Success([application.family_id, false, application.errors.full_messages.join(', ')])
            end
          rescue StandardError => e
            Failure("An error occurred while submitting the application for family_id: #{application.family_id} errors: #{e.message}")
          end

          def determine_applicants(result)
            return Success(result) unless result[1]
            application = result[0]

            applicants_results = application.applicants.map do |applicant|
              Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::DetermineApplicant.new.call({applicant: applicant})
            end
            failed_applicants = applicants_results.select(&:failure?)
            if failed_applicants.any?
              Success([application.family_id, false, failed_applicants.map(&:failure).join(', ')])
            else
              Success([application, true, "Applicants determined successfully but not persisted"])
            end
          end

          def determine_application(result)
            return Success(result) unless result[1]
            application = result[0]

            application.determine(reason: "created first QHP application for individual_market eligibility")
            if application.valid?
              application.save!
              Success([application, true, "Application created successfully"])
            else
              Success([application.family_id, false, application.errors.full_messages.join(", ")])
            end
          rescue StandardError => e
            Failure("An error occurred while determining the application for family #{application.family_id}, error: #{e.message}")
          end

          # Deactivates all existing tax household groups for the application's assistance year
          #
          # @param application [IndividualMarket::Application] the individual market application
          # @param family [Family] the family associated with the application
          # @return [Dry::Monads::Result] Success with message
          def deactivate_tax_household_groups(result)
            return Success(true) unless result[1] #false indicates failure in application creation
            application = result[0]
            family = application.family

            family.tax_household_groups.by_year(application.assistance_year).each do |thhg|
              thhg.end_on = application.effective_on > thhg.start_on ? (application.effective_on - 1.day) : thhg.start_on

              thhg.tax_households.each do |thh|
                thh.effective_ending_on = application.effective_on > thh.effective_starting_on ? (application.effective_on - 1.day) : thh.effective_starting_on
              end
            end

            Success('Deactivated old Tax Household Groups')
          end

          # Builds a new tax household group and tax household for the application
          #
          # @param application [IndividualMarket::Application] the individual market application
          # @param family [Family] the family associated with the application
          # @param family_members_result [Hash] hash of applicant_id => family_member
          #
          # @return [Dry::Monads::Result] Success with tax household group or Failure with error message
          def build_tax_household_group(result)
            return Success(true) unless result[1] #false indicates failure in application creation
            application = result[0]
            family = application.family

            thhg = family.tax_household_groups.build(
              source: 'qhp',
              application_gid: application.to_global_id.to_s,
              start_on: application.effective_on,
              end_on: nil,
              assistance_year: application.assistance_year
            )

            thh = thhg.tax_households.build(effective_starting_on: application.effective_on)

            application.applicants.each do |applicant|
              thh.tax_household_members.build(
                applicant_id: applicant.family_member_id,
                is_without_assistance: applicant.is_qhp_eligible,
                is_totally_ineligible: !applicant.is_qhp_eligible,
                is_csr_eligible: applicant.is_csr_eligible,
                csr_percent_as_integer: applicant.csr_percent
              )
            end

            Success('Successfully built tax household group and tax household.')
          end

          def regenerate_family_determination(result)
            return Success(true) unless result[1] #false indicates failure in application creation
            determined_application = result[0]
            family = determined_application.family
            family.assign_latest_application_gid
            family.save!
            ::Operations::Eligibilities::BuildFamilyDetermination.new.call(family: family)
          end

          def compare_migrated_values(result)
            if result[1]
              Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::CompareMigratedEvidenceValues.new.call(application: result[0])
            else
              Success([[result[0], '', false, result[2]]])
            end
          end

          def publish(rows)
            csv_headers = ["Family ID",
                           "Application HBX ID",
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
              event = event("events.migration_results.enqueue_result", attributes: {csv_file_name: "new_qhp_application_report", csv_headers: csv_headers, csv_row: row})

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