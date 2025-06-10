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

        # @return [Array<String>] List of valid individual market basis kinds
        INDIVIDUAL_MARKET_BASIS_KINDS = %w[ai_an_attested].freeze

        # @return [Array<String>] List of valid financial assistance basis kinds
        # this list will be expanded when financial assistance determinations are switched to this pattern
        FINANCIAL_ASSISTANCE_BASIS_KINDS = %w[ai_an_attested].freeze

        # @!attribute csr_type
        # @return [String] The determined CSR type
        # @see CSR_TYPE_KINDS for valid values
        field :csr_type, type: String

        validates :is_eligible, presence: true
        validate :bases_must_be_valid_basis_kinds
        validate :unique_basis_kinds

        # @return [Boolean] Determines if the CSR determination is eligible for csr_limited
        # as part of the individual market determination
        def determine_individual_market_eligibility
          self.is_eligible = (csr_type == "csr_limited" && all_individual_market_bases_present && individual_market_bases.all?(&:is_satisfied))
        end

        private

        # @return [Array<Eligibilities::V3::Basis>] List of CSR basis objects
        # @see INDIVIDUAL_MARKET_BASIS_KINDS for valid values
        def individual_market_bases
          bases.select { |basis| INDIVIDUAL_MARKET_BASIS_KINDS.include?(basis.basis_kind) }
        end

        # @return [Boolean] Determines if the CSR determination has unique basis kinds
        def unique_basis_kinds
          embedded_basis_kinds = bases.map(&:basis_kind)
          errors.add(:bases, "Duplicate basis kinds") if embedded_basis_kinds.uniq.length != embedded_basis_kinds.length
        end

        # @return [Boolean] Determines if all individual market bases are present
        def all_individual_market_bases_present
          embedded_basis_kinds = individual_market_bases.map(&:basis_kind)
          missing_basis_kinds = INDIVIDUAL_MARKET_BASIS_KINDS - embedded_basis_kinds
          missing_basis_kinds.empty?
        end

        def bases_must_be_valid_basis_kinds
          embedded_basis_kinds = bases.map(&:basis_kind)
          if csr_type == "csr_limited"
            errors.add(:bases, "Invalid basis kind: #{embedded_basis_kinds.join(', ')}") unless embedded_basis_kinds.all? { |basis_kind| INDIVIDUAL_MARKET_BASIS_KINDS.include?(basis_kind) }
          else
            errors.add(:bases, "Invalid basis kind: #{embedded_basis_kinds.join(', ')}") unless embedded_basis_kinds.all? { |basis_kind| FINANCIAL_ASSISTANCE_BASIS_KINDS.include?(basis_kind) }
          end
        end
      end
    end
  end
end
