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
            evidence     = find_evidence(valid_params, subject)

            Success(member: member, evidence: evidence)
          end

          private

          def validate(params)
            return Failure('Family is missing') unless params[:family].present?
            return Failure('Person ID is missing') unless params[:person_id].present?
            return Failure('Evidence key is missing') unless params[:evidence_key].present?
            return Failure('Eligibility kind is missing') unless params[:eligibility_kind].present?

            Success(params)
          end

          def find_evidence_state(subject, eligibility_kind, evidence_key)
            eligibility_state = subject.eligibility_states.by_type(eligibility_kind).first
            eligibility_state_error_substring = "Eligibility \"#{eligibility_kind.gsub(/\W+/, '')&.titleize}\""
            return Failure("#{eligibility_state_error_substring} not found for #{subject.full_name}") unless eligibility_state.present?

            evidence = eligibility_state.evidence_states.by_key(evidence_key).first
            return Failure("Evidence \"#{evidence_key.gsub(/\W+/, '')&.titleize}\" not found under #{eligibility_state_error_substring} for #{subject.full_name}") unless evidence.present?

            Success(::Adapters::EvidenceAdapter.new(evidence))
          end

          def find_identity_verification(subject)
            person = subject.person
            return Failure("#{subject_error_substring} is not identity verified") unless person.consumer_role&.application_verified? || person.consumer_role&.identity_verified?
            return Failure("Identity verification is not enabled") unless EnrollRegistry.feature_enabled?(:show_identity_verification)

            Success(::Adapters::EvidenceAdapter.new(person))
          end

          def find_inactive_verification(subject, evidence_key)
            return Failure("Inactive verification display is not enabled") unless EnrollRegistry.feature_enabled?(:show_inactive_verifications)
            type_name = evidence_key.gsub(/\W+/, ' ')&.titleize
            verification = subject.person.verification_types.inactive.select { |v_type| v_type.type_name.downcase == type_name.downcase }.first
            return Failure("Inactive verification \"#{type_name}\" not found for #{subject.full_name}") unless verification.present?

            Success(::Adapters::EvidenceAdapter.new(verification))
          end

          def find_inactive_evidence(subject, evidence_key)
            return Failure("Inactive evidence display is not enabled") unless EnrollRegistry.feature_enabled?(:show_inactive_verifications)
            family_member = GlobalID::Locator.locate(subject.gid)
            evidence = family_member&.find_latest_determined_application_with_evidence_key(evidence_key)
            return Failure("Inactive evidence \"#{evidence_key.gsub(/\W+/, '')&.titleize}\" not found for #{subject.full_name}") unless evidence.present?

            Success(::Adapters::EvidenceAdapter.new(evidence))
          end

          def find_evidence(valid_params, subject)
            case valid_params[:eligibility_kind]
            when 'ridp'
              yield find_identity_verification(subject)
            when 'individual_market_eligibility'
              yield find_inactive_evidence(subject, valid_params[:evidence_key])
            when 'aca_individual_market_eligibility', 'aptc_csr_credit'
              if valid_params[:inactive] == "true"
                yield find_inactive_verification(subject, valid_params[:evidence_key])
              else
                yield find_evidence_state(subject, valid_params[:eligibility_kind], valid_params[:evidence_key])
              end
            else
              yield Failure("Unsupported eligibility kind: #{valid_params[:eligibility_kind]}")
            end
          end
        end
      end
    end
  end
end
