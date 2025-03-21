# frozen_string_literal: true

module Operations
  module Families
    module Verifications
      module Summary
        # Retrieves a specific evidence item for a household member.
        # This query locates a particular evidence item for a specific person, either from
        # standard eligibility evidence sources or from identity verification when applicable.
        # The evidence is wrapped in an adapter to provide a consistent interface regardless
        # of the underlying evidence type.
        #
        # @see EvidenceAdapter Used to provide a consistent interface for different evidence types
        class EvidenceQuery
          include Dry::Monads[:do, :result]
          include SubjectMemberFinder

          def call(params)
            valid_params = yield validate(params)
            subject      = yield find_subject(family: valid_params[:family], person_id: valid_params[:person_id])
            member       = yield find_member(family: valid_params[:family], subject: subject)
            evidence     = yield find_evidence(valid_params, subject)

            Success(member: member, evidence: evidence)
          end

          private

          def validate(params)
            return Failure('Family is missing') unless params[:family].present?
            return Failure('Person ID is missing') unless params[:person_id].present?
            return Failure('Evidence key is missing') unless params[:evidence_key].present?

            Success(params)
          end

          def find_evidence(valid_params, subject)
            subject_error_substring = subject.full_name
            if valid_params[:evidence_key] == 'identity'
              return Failure("#{subject_error_substring} is not identity verified") unless subject.person.user&.consumer_identity_verified?
              return Failure("Identity verification is not enabled") unless EnrollRegistry.feature_enabled?(:show_identity_verification)

              Success(::Adapters::EvidenceAdapter.new(subject.person))
            else
              eligibility_state = subject.eligibility_states.by_type(valid_params[:eligibility_kind]).first
              eligibility_state_error_substring = "Eligibility \"#{valid_params[:eligibility_kind].gsub(/\W+/, '')&.titleize}\""
              return Failure("#{eligibility_state_error_substring} not found for #{subject_error_substring}") unless eligibility_state.present?

              evidence = eligibility_state.evidence_states.by_key(valid_params[:evidence_key]).first
              return Failure("Evidence \"#{valid_params[:evidence_key].gsub(/\W+/, '')&.titleize}\" not found under #{eligibility_state_error_substring} for #{subject_error_substring}") unless evidence.present?

              Success(::Adapters::EvidenceAdapter.new(evidence))
            end
          end
        end
      end
    end
  end
end
