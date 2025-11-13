# frozen_string_literal: true

module Eligibilities
  module V3
    # Eligibility  utility class for eligibility
    # Module is used to include the common methods, fields, validations, associations etc related to AptcCsr and IndividualMarket eligibility.
    module EligibilityUtils
      extend ActiveSupport::Concern

      # key stores information about which type of eligibility it is.
      ELIGIBILITY_CLASSES = {
        individual_market_eligibility: ::Eligibilities::V3::IndividualMarketEligibility,
        aptc_csr_eligibility: ::Eligibilities::V3::AptcCsrEligibility
      }.freeze

      # Moves evidences to outstanding status if they are pending or negative_response_received.
      #
      # This is used in the evidence workflow when evidences which were once outstanding and were later downgraded become required again.
      #
      # @param action [String] The action that triggered requiring evidences
      # @param message [String] The message describing why evidences are being required
      # @return [void]
      def escalate_evidences_to_outstanding(action, message)
        evidences.each do |evidence|
          next unless evidence.pending? || evidence.negative_response_received?

          evidence.mark_as_outstanding
          evidence.build_verification_history(action, message, 'system')
        end
        determine_eligibility_state(message)
      end

      # Moves evidences to negative_response_received status if they are outstanding.
      #
      # This is used in the evidence workflow when evidences which are outstanding become not required.
      #
      # @param action [String] The action that triggered waiving evidences
      # @param message [String] The message describing why evidences are being waived
      # @return [void]
      def downgrade_evidences_to_nrr(action, message)
        evidences.each do |evidence|
          next unless evidence.outstanding?

          evidence.mark_as_negative_response_received
          evidence.build_verification_history(action, message, 'system')
        end
        determine_eligibility_state(message)
      end
    end
  end
end
