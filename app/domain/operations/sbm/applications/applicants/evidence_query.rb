# frozen_string_literal: true

module Operations
  module Sbm
    module Applications
      module Applicants
        # Retrieves a specific evidence item for a household member.
        # This query locates a particular evidence item for a specific applicant, either from
        # standard eligibility evidence sources or from identity verification when applicable.
        # The evidence is wrapped in an adapter to provide a consistent interface regardless
        # of the underlying evidence type.
        #
        # @see EvidenceAdapter Used to provide a consistent interface for different evidence types
        class EvidenceQuery
          include Dry::Monads[:do, :result]

          def call(params)
            valid_params = yield validate(params)
            evidence     = yield find_evidence(valid_params)

            Success(member: valid_params[:applicant].family_member, evidence: evidence,
                    display_previous_evidences: true)
          end

          private

          def validate(params)
            return Failure('Family is missing') unless params[:family].present?
            return Failure('Person ID is missing') unless params[:person_id].present?
            return Failure('Evidence key is missing') unless params[:evidence_key].present?
            return Failure('Eligibility kind is missing') unless params[:eligibility_kind].present?
            return Failure('Application is missing') unless params[:application].present?
            return Failure('Applicant is missing') unless params[:applicant].present?


            Success(params)
          end

          def find_evidence_state(valid_params)
            applicant = valid_params[:applicant]
            eligibility_kind = valid_params[:eligibility_kind]
            eligibility = applicant.eligibilities.by_key(valid_params[:eligibility_kind]).first

            eligibility_state_error_substring = "Eligibility \"#{eligibility_kind.gsub(/\W+/, '')&.titleize}\""
            return Failure("#{eligibility_state_error_substring} not found for #{applicant.full_name}") unless eligibility.present?

            evidence_key = valid_params[:evidence_key]
            evidence = eligibility.evidences.by_key(valid_params[:evidence_key]).first
            return Failure("Evidence \"#{evidence_key.gsub(/\W+/, '')&.titleize}\" not found under #{eligibility_state_error_substring} for #{applicant.full_name}") unless evidence.present?

            Success(::Adapters::EvidenceAdapter.new(evidence))
          end

          def find_inactive_evidence(valid_params)
            return Failure("Inactive evidence display is not enabled") unless EnrollRegistry.feature_enabled?(:show_inactive_verifications)

            applicant = valid_params[:applicant]
            eligibility = applicant.eligibilities.by_key(valid_params[:eligibility_kind]).first
            evidence_key = valid_params[:evidence_key]
            evidence = eligibility.evidences.by_key(valid_params[:evidence_key]).first
            return Failure("Inactive evidence \"#{evidence_key.gsub(/\W+/, '')&.titleize}\" not found for #{applicant.full_name}") unless evidence.present?

            Success(::Adapters::EvidenceAdapter.new(evidence))
          end

          def find_evidence(valid_params)
            if valid_params[:inactive] == "true"
              find_inactive_evidence(valid_params)
            else
              find_evidence_state(valid_params)
            end
          end
        end
      end
    end
  end
end
