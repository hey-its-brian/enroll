# frozen_string_literal: true

module Operations
  module Families
    module Verifications
      module Summary
        # Retrieves and organizes verification evidence for a specific individual.
        # This query collects all verification evidence for a specific household member,
        # including both eligibility evidence states and identity verification when available.
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
            evidences = subject.eligibility_states.by_type_uploadable.flat_map do |state|
              state.evidence_states.map { |evidence| ::Adapters::EvidenceAdapter.new(evidence) }
            end

            person = subject.person
            evidences << ::Adapters::EvidenceAdapter.new(person) if person.user&.consumer_identity_verified? && EnrollRegistry.feature_enabled?(:show_identity_verification)

            Success(evidences)
          end

          def sort_evidences(evidences)
            Success(evidences.sort_by do |evidence|
              [
                evidence.is_action_needed? ? 0 : 1,
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
