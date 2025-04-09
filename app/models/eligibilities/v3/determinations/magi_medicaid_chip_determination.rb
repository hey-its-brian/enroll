# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Determinations
      # @class MagiMedicaidChipDetermination
      # Represents a determination for children's eligibility for Medicaid and CHIP programs
      # CHIP (Children's Health Insurance Program) provides low-cost health coverage to children in
      # families that earn too much for Medicaid but cannot afford private insurance. Eligibility is
      # determined using Modified Adjusted Gross Income (MAGI) methodology as required by the ACA.
      #
      # @see Eligibilities::Determination
      class MagiMedicaidChipDetermination < ::Eligibilities::V3::Determination
      end
    end
  end
end
