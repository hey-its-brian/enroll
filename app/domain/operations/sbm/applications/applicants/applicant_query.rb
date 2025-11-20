# frozen_string_literal: true

module Operations
  module Sbm
    module Applications
      module Applicants
        # Retrieves and organizes verification evidence for a specific applicant.
        # This query collects all verification evidence for a specific applicant,
        # including eligibility evidence states, inactive verifications, and identity verification when available.
        #
        # @see EvidenceAdapter Used to normalize different evidence types
        class ApplicantQuery
          include VerificationHelper
          include Dry::Monads[:do, :result]
          include ResourceRegistryHelper

          def call(params)
            valid_params     = yield validate(params)
            application      = yield find_application(params[:application_gid])
            applicant        = yield find_applicant(application, valid_params[:applicant_id])
            member           = yield find_member(applicant)
            evidences        = yield find_all_evidences(applicant)
            sorted_evidences = yield sort_evidences(evidences)

            Success(application: application, member: member, evidences: sorted_evidences, display_previous_evidences: true)
          end

          private

          def validate(params)
            # return Failure("Family is missing") unless params[:family].present?
            # return Failure("Person ID is missing") unless params[:person_id].present?

            Success(params)
          end

          def find_application(application_gid)
            application = GlobalID::Locator.locate(application_gid)
            return Failure("Application not found") if application.blank?

            Success(application)
          end

          def find_applicant(application, applicant_id)
            applicant = application.applicants.detect{|app| app.id.to_s == applicant_id}
            return Failure("Applicant not found") if applicant.blank?

            Success(applicant)
          end

          def find_member(applicant)
            Success(applicant.family_member)
          end

          def find_all_evidences(applicant)
            evidences = collect_uploadable_eligibility_evidences(applicant)
            evidences += collect_inactive_evidences(applicant)
            evidences += collect_identity_evidence(applicant)

            Success(evidences)
          end

          # Collects all evidences from uploadable eligibilities.
          def collect_uploadable_eligibility_evidences(applicant)
            applicant.uploadable_eligibilities.flat_map do |eligibility|
              eligibility.evidences.map { |evidence| ::Adapters::EvidenceAdapter.new(evidence) }
            end
          end

          def collect_inactive_evidences(applicant)
            return fetch_inactive_verifications_from_determination(applicant) if qhp_application_feature_enabled? && EnrollRegistry.feature_enabled?(:show_inactive_verifications)

            fetch_inactive_verifications_from_person(applicant)
          end

          def fetch_inactive_verifications_from_determination(applicant)
            family_member = applicant.family_member
            evidences = []
            possible_ivl_evidence_keys = ["citizenship_evidence", "immigration_evidence", "american_indian_evidence", "social_security_number_evidence", "alive_evidence"]
            active_evidence_keys = collect_uploadable_eligibility_evidences(applicant).map do |evidence|
              evidence.evidence_item_key&.to_s&.gsub('_status', '')&.gsub('_evidence', '')&.to_s
            end
            missing_evidence_types = possible_ivl_evidence_keys.reject { |key| active_evidence_keys.include?(key.gsub('_evidence', '')) }

            missing_evidence_types.each do |evidence_type|
              evidence = family_member&.find_latest_determined_application_with_evidence_key(evidence_type)
              evidences << ::Adapters::EvidenceAdapter.new(evidence) if evidence.present?
            end

            evidences
          end

          def fetch_inactive_verifications_from_person(applicant)
            person = applicant.person
            person.verification_types.inactive.map do |verification|
              ::Adapters::EvidenceAdapter.new(verification)
            end
          end

          def collect_identity_evidence(applicant)
            person = applicant.person
            return [] unless EnrollRegistry.feature_enabled?(:show_identity_verification)

            ridp_verified = person.consumer_role&.application_verified? || person.consumer_role&.identity_verified?

            if ridp_verified
              [::Adapters::EvidenceAdapter.new(person)]
            else
              []
            end
          end

          def sort_evidences(evidences)
            Success(evidences.sort_by do |evidence|
              [
                evidence.grouped_status.to_s,
                evidence.due_on || Float::INFINITY,
                display_verification_type_name(evidence.evidence_item_key)
              ]
            end)
          end
        end
      end
    end
  end
end
