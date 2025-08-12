# frozen_string_literal: true

module FinancialAssistance
  # @title Financial Assistance Evidences Module
  # @description This module contains evidence classes specific to financial assistance applications
  #   that verify various eligibility factors for APTC/CSR benefits.
  module Evidences
    # Represents evidence used to verify an applicant's employer-sponsored insurance MEC status
    #
    # This evidence type validates whether an applicant has access to affordable
    # employer-sponsored insurance that qualifies as Minimum Essential Coverage (MEC).
    # Individuals with affordable ESI MEC are typically ineligible for APTC/CSR.
    #
    # @example Creating a new ESI MEC evidence
    #   eligibility.evidences.build(_type: 'FinancialAssistance::Evidences::EsiMecEvidence')
    #
    class EsiMecEvidence < ::Eligibilities::V3::Evidence
      include ::Eligibilities::V3::EvidenceUtils

      # Determines if the ESI MEC evidence verification is satisfied
      #
      # @return [Boolean] true if ESI MEC verification is satisfied, false otherwise
      def determine_evidence
        # this is a command that will determine the evidence is satisfied or not.
        # fdsh_verification || document_verification || admin_verification || visitor_verification
      end

      def call_hub(params)
        ::FinancialAssistance::Operations::Evidences::EsiMec::CallHub.new.call(params.merge(evidence: self))
      end
    end
  end
end
