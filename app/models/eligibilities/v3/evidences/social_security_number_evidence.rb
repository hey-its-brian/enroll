# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    module Evidences
      # Represents evidence used to verify an individual's Social Security Number (SSN)
      #
      # This evidence type is only verified if the individual has attested to having an SSN.
      # It follows the verification workflow process for SSN verification, including document
      # uploads, state transitions, and integration with verification services.
      #
      # @example Creating a new social security number evidence
      #   eligibility.evidences.build(_type: 'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence')
      #
      # @see Eligibilities::Evidence Parent class for common evidence functionality
      class SocialSecurityNumberEvidence < ::Eligibilities::V3::Evidence
        include ::Eligibilities::V3::EvidenceUtils

        def call_hub(params)
          applicant = eligibility.eligible
          Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification.new.call(
            {application: applicant.application,
             requested_ids: [fetch_applicant_hbx_id(applicant)],
             call_type: 'hub_call',
             updated_by: params[:updated_by]}
          )
        end
      end
    end
  end
end
