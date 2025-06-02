# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Determinations
      # @!class IndividualMarketDetermination
      # A determination that evaluates whether an individual is eligible to
      # shop for health and dental insurance plans in the marketplace.
      #
      # @see Eligibilities::Determination
      class IndividualMarketDetermination < ::Eligibilities::V3::Determination

        BASIS_KINDS = %w[
          applying_coverage
          is_alive
          state_resident
          not_incarcerated
          lawfully_present_in_us
        ].freeze

        validate :bases_must_be_valid_basis_kinds

        def determine_eligibility
          self.is_eligible = all_bases_present && bases.all?(&:is_satisfied)
        end

        private

        def bases_must_be_valid_basis_kinds
          embedded_basis_kinds = bases.map(&:basis_kind)
          extra_basis_kinds = embedded_basis_kinds - BASIS_KINDS
          errors.add(:bases, "Invalid basis kind: #{extra_basis_kinds.join(', ')}") if extra_basis_kinds.any?
        end

        def all_bases_present
          embedded_basis_kinds = bases.map(&:basis_kind)
          missing_basis_kinds = BASIS_KINDS - embedded_basis_kinds
          missing_basis_kinds.empty?
        end
      end
    end
  end
end
