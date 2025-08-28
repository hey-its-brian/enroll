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
      def auto_extend_due_date(action, extend_by, modified_by)
        return if self.due_date_extended_at.present?
        return if OUTSTANDING_STATUSES.exclude?(self.current_state)

        current_due_on = self.due_on
        self.due_date_extended_at = DateTime.now
        self.due_on = current_due_on + extend_by.days
        build_verification_history(action, "Auto extended due date from #{current_due_on.strftime('%m/%d/%Y')} to #{due_on.strftime('%m/%d/%Y')}", modified_by)
      end

      # Initiates a hub call for income verification through FDSH services
      #
      # This method triggers the income verification process by calling the FDSH hub
      # to verify the applicant's income information. It handles the complete workflow
      # including payload validation, hub request communication, and failure result processing.
      #
      # @param params [Hash] Parameters for the hub call request
      # @option params [String] :action_name The administrative action being performed
      # @option params [String] :update_reason Reason for requesting verification
      # @option params [String] :updated_by Identifier of the user initiating the request
      #
      # @return [Object, false] Returns the operation result value on success, false on failure
      #
      # @example Controller usage
      #   permitted_params = {
      #     action_name: params[:admin_action],
      #     update_reason: "Requested Hub for verification",
      #     updated_by: current_user.oim_id
      #   }
      #   result = @evidence.call_hub(permitted_params)
      #   if result
      #     flash[:notice] = "Hub verification request submitted successfully"
      #   else
      #     flash[:error] = "Hub verification request failed"
      #   end
      #
      # @note This method automatically merges the current evidence instance into the parameters
      # @see FinancialAssistance::Operations::Evidences::Income::CallHub For the underlying operation
      def call_hub(params)
        ::FinancialAssistance::Operations::Evidences::Income::CallHub.new.call(params.merge(evidence: self))
      end

      def determine_income_evidence_current_state
        applicant = self.eligibility.eligible
        application = applicant.application
        family_id = application&.family_id

        enrollments = fetch_enrolled_enrollments(family_id)
        aptc_or_csr_used = applicant.enrolled_in_any_aptc_csr_enrollments?(enrollments)

        if aptc_or_csr_used
          self.mark_as_outstanding
        else
          self.mark_as_negative_response_received
        end
      end

      def fetch_enrolled_enrollments(family_id)
        HbxEnrollment.where(
          :aasm_state.in => HbxEnrollment::ENROLLED_STATUSES,
          family_id: family_id
        )
      end

      # Method is to retain evidence information from the current evidence.
      #  1. Reasonable Opportunity Period (ROP) due date
      #  2. Evidence's current state
      #  3. Due date extended information (if applicable). This currently applies to income evidence only.
      # This is used in the context of the system generated applications like renewals and expired_rop.
      #
      # @param current_evidence [Eligibilities::V3::Evidence] The evidence from the current application
      #
      # @return [void]
      def retain_evidence_information(current_evidence)
        current_app = current_evidence.eligibility.eligible.application

        app_hbx_id = current_app.hbx_id
        app_type = case current_app.class
                   when IndividualMarket::Application
                     'qhp'
                   when FinancialAssistance::Application
                     'faa'
                   end

        # Raises a RuntimeError if the application type is not 'faa'. Only FA applications are expected to have income_evidence.
        raise "Unexpected application type: #{app_type}" unless app_type == 'faa'

        pre_state = self.current_state
        new_state = current_evidence.current_state

        self.current_state = new_state

        state_and_date_change_text = "State updated from #{pre_state} to #{new_state} copied from previous application #{app_hbx_id} application type #{app_type} due to annual eligibility redetermination."

        if OUTSTANDING_STATUSES.include?(new_state.to_sym) && current_evidence.due_on.present?
          self.due_on = current_evidence.due_on

          state_and_date_change_text = if current_evidence.due_date_extended_at.present?
                                         self.due_date_extended_at = current_evidence.due_date_extended_at
                                         "State updated from #{pre_state} to #{new_state}, " \
                                                                   "due date of #{current_evidence.due_on} copied, " \
                                                                   "and #{current_evidence.due_date_extended_at} automatic due date extended at copied " \
                                                                   "from previous application #{app_hbx_id} application type #{app_type} " \
                                                                   "due to annual eligibility redetermination."
                                       else
                                         "State updated from #{pre_state} to #{new_state} " \
                                                         "and due date of #{current_evidence.due_on} copied " \
                                                         "from previous application #{app_hbx_id} application type #{app_type} " \
                                                         "due to annual eligibility redetermination."
                                       end
        end

        self.build_verification_history(
          'retain_evidence_info_on_renewal',
          state_and_date_change_text,
          'system'
        )
      end
    end
  end
end
