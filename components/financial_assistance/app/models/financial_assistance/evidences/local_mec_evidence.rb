# frozen_string_literal: true

module FinancialAssistance
  # @title Financial Assistance Evidences Module
  # @description This module contains evidence classes specific to financial assistance applications
  #   that verify various eligibility factors for APTC/CSR benefits.
  module Evidences
    # Represents evidence used to verify an applicant's local Minimum Essential Coverage status
    #
    # This evidence type validates whether an applicant has access to affordable
    # local government-provided coverage that qualifies as Minimum Essential Coverage (MEC).
    # This may include local Medicaid, CHIP, or other state/local programs.
    #
    # @example Creating a new Local MEC evidence
    #   eligibility.evidences.build(_type: 'FinancialAssistance::Evidences::LocalMecEvidence')
    #
    class LocalMecEvidence < ::Eligibilities::V3::Evidence
      include ::Eligibilities::V3::EvidenceUtils

      # Determines if the Local MEC evidence verification is satisfied
      #
      # @return [Boolean] true if Local MEC verification is satisfied, false otherwise
      def determine_evidence
        # this is a command that will determine the evidence is satisfied or not.
        # fdsh_verification || document_verification || admin_verification || visitor_verification
      end

      def call_hub(params)
        ::FinancialAssistance::Operations::Evidences::LocalMec::CallHub.new.call(params)
      end
    end
  end
end
