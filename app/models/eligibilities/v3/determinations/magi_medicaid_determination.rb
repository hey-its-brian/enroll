# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Determinations
      # @class MagiMedicaidDetermination
      # Represents a determination for Medicaid eligibility using MAGI methodology
      # Medicaid eligibility is determined using Modified Adjusted Gross Income (MAGI)
      # methodology as required by the ACA. This covers low-income individuals and families
      # who meet specific income thresholds relative to the Federal Poverty Level (FPL).
      #
      # @see Eligibilities::Determination
      class MagiMedicaidDetermination < ::Eligibilities::V3::Determination
      end
    end
  end
end
