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
    end
  end
end
