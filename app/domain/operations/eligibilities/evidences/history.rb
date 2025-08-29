# frozen_string_literal: true

module Operations
  module Eligibilities
    module Evidences
      # History operation handles retrieving documents for evidence from applications
      class History
        include Dry::Monads[:do, :result]

        # Retrieves documents for evidence verification
        #
        # @param params [Hash] parameters for filtering documents
        # @param evidence [Evidence] the evidence record
        # @return [Dry::Monads::Result] Success with result hash or Failure with error message
        def call(params)
          validated_params = yield validate(params)
          evidence_histories = yield fetch_evidence_history(validated_params)
          evidence_request_results = yield fetch_evidence_request_results(params)
          formatted_results = yield format_results(evidence_histories, evidence_request_results)

          Success(
            formatted_results
          )
        end

        private

        def validate(params)
          return Failure("Application not found") if params[:application].blank?
          return Failure("Applicant not found") if params[:applicant].blank?
          return Failure("Evidence not found") if params[:evidence].blank?

          Success(params)
        end

        def fetch_evidence_history(params)
          evidence = params[:evidence]
          applicant = params[:applicant]
          eligibility_key = evidence.eligibility.key
          eligibility = applicant.respond_to?(eligibility_key) ? applicant.send(eligibility_key) : nil

          selected_evidence = eligibility&.evidences&.detect{|ev| ev.key.to_s == evidence.key.to_s}
          Success(selected_evidence&.verification_histories || [])
        end

        def fetch_evidence_request_results(params)
          evidence = params[:evidence]
          applicant = params[:applicant]
          eligibility_key = evidence.eligibility.key
          eligibility = applicant.respond_to?(eligibility_key) ? applicant.send(eligibility_key) : nil

          selected_evidence = eligibility&.evidences&.detect{|ev| ev.key.to_s == evidence.key.to_s}
          Success(selected_evidence&.request_results || [])
        end

        def format_results(evidence_histories, evidence_request_results)
          elements = evidence_histories + evidence_request_results
          Success(Array(elements).map { |element| EvidenceHistoryDecorator.new(element) }
                         .sort_by(&:date_of_action)
                         .reverse)
        end
      end
    end
  end
end
