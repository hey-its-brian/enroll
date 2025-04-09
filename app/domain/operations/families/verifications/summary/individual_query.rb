# frozen_string_literal: true

module Operations
  module Families
    module Verifications
      module Summary
        # Retrieves and organizes verification evidence for a specific individual.
        # This query collects all verification evidence for a specific household member,
        # including eligibility evidence states, inactive verifications, and identity verification when available.
        #
        # @see EvidenceAdapter Used to normalize different evidence types
        class IndividualQuery
          include VerificationHelper
          include Dry::Monads[:do, :result]
          include SubjectMemberFinder

          def call(params)
            valid_params     = yield validate(params)
            subject          = yield find_subject(family: valid_params[:family], person_id: valid_params[:person_id])
            member           = yield find_member(family: valid_params[:family], subject: subject)
            evidences        = yield find_all_evidences(subject)
            sorted_evidences = yield sort_evidences(evidences)

            Success(member: member, evidences: sorted_evidences)
          end

          private

          def validate(params)
            return Failure("Family is missing") unless params[:family].present?
            return Failure("Person ID is missing") unless params[:person_id].present?

            Success(params)
          end

          def find_all_evidences(subject)
            # Collect all evidence states from the determination
            evidences = subject.eligibility_states.by_type_uploadable.flat_map do |state|
              state.evidence_states.map { |evidence| ::Adapters::EvidenceAdapter.new(evidence) }
            end

            person = subject.person

            # Inactive verifications are not available from the determination, fetch them directly
            inactive_verifications = person.verification_types.inactive.map do |verification|
              ::Adapters::EvidenceAdapter.new(verification)
            end
            evidences += inactive_verifications if EnrollRegistry.feature_enabled?(:show_inactive_verifications)

            # Fetch identity verification if available
            ridp_verified = person.consumer_role&.application_verified? || person.consumer_role&.identity_verified?
            evidences << ::Adapters::EvidenceAdapter.new(person) if ridp_verified && EnrollRegistry.feature_enabled?(:show_identity_verification)

            Success(evidences)
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
