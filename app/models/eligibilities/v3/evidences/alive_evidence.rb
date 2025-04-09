# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Evidences
      # Represents evidence used to verify an individual's living status
      #
      # AliveEvidence is specialized evidence that verifies whether a person is alive.
      # It follows the standard verification workflow process for evidence, including document uploads,
      # state transitions, and integration with verification services that can confirm a person's
      # living status.
      #
      # @example Creating alive evidence for an eligibility
      #   eligibility.evidences.build(_type: 'Eligibilities::Evidences::AliveEvidence')
      #
      # @see Eligibilities::Evidence The parent class with common evidence functionality
      class AliveEvidence < ::Eligibilities::V3::Evidence
        include ::Eligibilities::V3::EvidenceUtils
      end
    end
  end
end
