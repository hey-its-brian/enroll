# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Determinations
      # @!class AptcDetermination
      # @abstract Subclass of {Eligibilities::Determination} that represents Advanced Premium Tax Credit eligibility
      #
      # @description
      #   Advanced Premium Tax Credit (APTC) determination is used to assess if an applicant
      #   qualifies for tax credits that can be used to lower their monthly health insurance
      #   premium costs. When determined eligible, the applicant may receive financial assistance
      #   to reduce premium costs.
      #
      # @see Eligibilities::Determination
      class AptcDetermination < ::Eligibilities::V3::Determination
      end
    end
  end
end
