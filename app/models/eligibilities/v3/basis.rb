# frozen_string_literal: true

module Eligibilities
  module V3
    # Represents a specific basis that needs to be verified for eligibility determination
    #
    # A Basis is embedded within a Determination and represents a specific rule or check
    # that must be satisfied as part of the eligibility verification process.
    #
    # @example Create a new basis
    #   determination.bases.build(
    #     basis_kind: 'state_residency',
    #     is_satisfied: true
    #   )
    #
    # @see Eligibilities::Determination
    class Basis
      include Mongoid::Document
      include Mongoid::Timestamps

      embedded_in :determination, class_name: 'Eligibilities::V3::Determination'

      # @!attribute basis_kind
      #   @return [String] The type of basis being evaluated (e.g. 'lawful_presence', 'state_residency', 'is_alive', etc.)
      field :basis_kind, type: String

      # @!attribute is_satisfied
      #   @return [Boolean] Whether this specific basis has been satisfied
      field :is_satisfied, type: Boolean
    end
  end
end
