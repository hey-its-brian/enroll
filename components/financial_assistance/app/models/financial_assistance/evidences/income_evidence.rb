# frozen_string_literal: true

module FinancialAssistance
  # @title Financial Assistance Evidences Module
  # @description This module contains evidence classes specific to financial assistance applications
  #   that verify various eligibility factors for APTC/CSR benefits.
  module Evidences
    # Represents evidence used to verify an applicant's income information
    #
    # This evidence type is responsible for validating the applicant's reported income
    # through various verification methods including FDSH data matches, document
    # verification, or administrative actions.
    #
    # @example Creating a new income evidence
    #   eligibility.evidences.build(_type: 'FinancialAssistance::Evidences::IncomeEvidence')
    #
    class IncomeEvidence < ::Eligibilities::V3::Evidence
      include ::Eligibilities::V3::EvidenceUtils

      OUTSTANDING_STATUSES = %i[outstanding rejected].freeze

      # Determines if the income evidence verification is satisfied
      #
      # @return [Boolean] true if income verification is satisfied, false otherwise
      def determine_evidence
        # this is a command that will determine the evidence is satisfied or not.
        # fdsh_verification || document_verification || admin_verification || visitor_verification
      end

      # Extends the due date for income evidence only if not already extended and if the current_state is outstanding/rejected
      #
      # @param action [String] The action that triggered the due date extension
      # @param extend_by [Integer] Number of days to extend the due date by
      # @param modified_by [String] Identifier of the user or process that modified the due
      def extend_due_date(action, extend_by, modified_by)
        return if self.due_date_extended_at.present?
        return if OUTSTANDING_STATUSES.exclude?(self.current_state)

        current_due_on = self.due_on
        self.due_date_extended_at = DateTime.now
        self.due_on = current_due_on + extend_by.days
        add_to_history(action, "Auto extended due date from #{current_due_on.strftime('%m/%d/%Y')} to #{due_on.strftime('%m/%d/%Y')}", modified_by)
      end
    end
  end
end
