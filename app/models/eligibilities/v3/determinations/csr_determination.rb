# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Determinations
      # @author IdeaCrew
      #
      # Cost Sharing Reduction (CSR) determination class that represents CSR eligibility status
      # for applicants. CSR eligibility allows individuals to qualify for reduced out-of-pocket
      # costs (like copayments and coinsurance) when purchasing Silver tier health plans.
      #
      # @see Eligibilities::Determination
      class CsrDetermination < ::Eligibilities::V3::Determination

        # @return [Array<String>] List of valid CSR types
        # @note CSR types represent different levels of cost sharing reduction:
        #   - csr_100: 100% cost sharing reduction (AI/AN limited cost sharing)
        #   - csr_94: 94% actuarial value variant
        #   - csr_87: 87% actuarial value variant
        #   - csr_73: 73% actuarial value variant
        #   - csr_0: No cost sharing reduction
        #   - csr_limited: Limited cost sharing plan variant
        CSR_TYPE_KINDS = %w[csr_100 csr_94 csr_87 csr_73 csr_0 csr_limited].freeze

        # @!attribute csr_type
        # @return [String] The determined CSR type
        # @see CSR_TYPE_KINDS for valid values
        field :csr_type, type: String
      end
    end
  end
end
