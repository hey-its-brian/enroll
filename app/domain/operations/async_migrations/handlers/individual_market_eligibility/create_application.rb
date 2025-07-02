# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module IndividualMarketEligibility
        # This class is responsible for creating QHP applications.
        class CreateApplication
          include Dry::Monads[:do, :result]
          include EventSource::Command
          include ::ResourceRegistryHelper

          def call(params)
            # Extract the necessary parameters

            family_id = yield validate(params)
            family = yield find_family(family_id)
            application = yield transform_family(family)
            draft_application = yield build_application(application)
            determined_application = yield persist(draft_application)
            yield regenerate_family_determination(determined_application)
            comparison_result = yield compare_migrated_values(determined_application)
            yield publish(comparison_result)

            Success(["QHP application created successfully for the family: #{family_id} with application ID:", determined_application.hbx_id])
          end

          private

          def validate(params)
            return Failure('family_id is expected in BSON format') unless BSON::ObjectId.legal?(params[:document_id])

            Success(params[:document_id])
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

          def application_attributes(family)
            application_attrs = {
              family_id: family.id,
              assistance_year: family.application_applicable_year,
              origin: :migration,
              generation_reason: :manual,
              submitted_at: DateTime.current,
              current_state: :determined
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

          def persist(draft_application)
            if draft_application.valid?
              draft_application.state_histories.build(
                event: 'determine',
                from_state: :initial,
                to_state: :determined,
                transition_at: Time.now,
                effective_on: Time.now,
                reason: "created first QHP application for individual_market eligibility"
              )
              draft_application.save!

              Success(draft_application)
            else
              Failure(draft_application.errors)
            end
          end

          def regenerate_family_determination(determined_application)
            family = determined_application.family
            family.assign_latest_application_gid
            family.save!

            Success(true)
            # place holder to build family determination
          end

          def compare_migrated_values(application)
            Operations::AsyncMigrations::Handlers::IndividualMarketEligibility::CompareMigratedEvidenceValues.new.call(application: application)
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