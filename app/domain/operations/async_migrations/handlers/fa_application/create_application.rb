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
            yield  generate_eligibilities(draft_application, application)
            determined_application = yield  move_to_determined(draft_application, application)
            Success(determined_application)
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
            copy_result = ::FinancialAssistance::Operations::Applications::Copy.new.call(
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
              new_aptc_csr_eligibility = new_applicant.build_aptc_csr_eligibility
              migrator.perform(old_aptc_csr_eligibility, new_aptc_csr_eligibility)
              old_aptc_csr_eligibility.evidences.each do |old_evidence|
                new_evidence = build_new_evidence(new_aptc_csr_eligibility, old_evidence)
                migrator.perform(old_evidence, new_evidence)
              end
            end

            Success(draft_application)
          rescue StandardError => e
            Failure("generation failed for the application: #{application.hbx_id} with error: #{e.message}")
          end

          def build_new_evidence(aptc_csr_eligibility, old_evidence)
            aptc_csr_eligibility.evidences.build(
              _type: old_evidence._type,
              title: old_evidence.title,
              key: old_evidence.key
            )
          end

          def move_to_determined(draft_application, application)
            draft_application.assign_attributes(assistance_year: application.assistance_year, aasm_state: "determined", origin: :migration, generation_reason: :manual)
            draft_application.workflow_state_transitions.build(
              event: 'determine',
              from_state: 'draft',
              to_state: 'determined',
              transition_at: Time.now,
              reason: "migrating from the latest determined application #{application.hbx_id} to create individual_market eligibilities"
            )
            disable_callback
            draft_application.save!
            enable_callback
            Success(draft_application)
          rescue StandardError => e
            enable_callback
            Failure("Failed to move to determined: #{e.message}")
          end

          def disable_callback
            ::FinancialAssistance::Applicant.skip_callback(:update, :after, :propagate_applicant, raise: false)
            ::FinancialAssistance::Relationship.skip_callback(:save, :after, :propagate_applicant)
          end

          def enable_callback
            ::FinancialAssistance::Applicant.set_callback(:update, :after, :propagate_applicant, raise: false)
            ::FinancialAssistance::Relationship.set_callback(:save, :after, :propagate_applicant)
          end
        end
      end
    end
  end
end