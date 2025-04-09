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
      end
    end
  end
end
