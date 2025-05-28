# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Evidences
      # Represents evidence used to verify an individual's American Indian or Alaskan Native status
      #
      # AmericanIndianEvidence is specialized evidence that verifies whether a person
      # is a member of a federally recognized American Indian tribe or an Alaskan Native.
      # This evidence is only applicable when the person has attested to having this status.
      # It follows the standard verification workflow process for evidence, including document uploads,
      # state transitions, and integration with verification services that can confirm tribal membership.
      #
      # @example Creating American Indian evidence for an eligibility
      #   eligibility.evidences.build(_type: 'Eligibilities::V3::Evidences::AmericanIndianEvidence')
      #
      # @see Eligibilities::Evidence The parent class with common evidence functionality
      class AmericanIndianEvidence < ::Eligibilities::V3::Evidence
        include ::Eligibilities::V3::EvidenceUtils
      end
    end
  end
end
