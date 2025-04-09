# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Evidences
      # Represents evidence used to verify an individual's US citizenship status
      #
      # This evidence type is only verified if the individual has attested to being a US Citizen.
      # It follows the verification workflow process for citizenship verification, including document
      # uploads, state transitions, and integration with verification services.
      #
      # @example Creating a new citizenship evidence
      #   eligibility.evidences.build(_type: 'Eligibilities::Evidences::CitizenshipEvidence')
      #
      # @see Eligibilities::Evidence Parent class for common evidence functionality
      class CitizenshipEvidence < ::Eligibilities::V3::Evidence
        include ::Eligibilities::V3::EvidenceUtils
      end
    end
  end
end
