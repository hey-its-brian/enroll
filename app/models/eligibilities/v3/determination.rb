# frozen_string_literal: true

module Eligibilities
  # @title Eligibilities V3 Module
  # @description This module represents version 3.0 of the Eligibility Evidence pattern.
  #   It contains models and functionality for processing eligibility, evidence, and determination
  #   using the latest standards and requirements.
  # @since 3.0.0
  module V3
    # Represents an eligibility determination for a specific program or benefit
    #
    # A Determination is a result of the evaluations of a set of bases to determine if
    # an applicant is eligible for a particular program (e.g. QHP, CSR, APTC, or MagiMedicaid).
    # Single Table Inheritance (STI) pattern is used to store different types of determinations in the same collection.
    #
    # @example Create a new determination with bases
    #   eligibility.determinations.build(is_eligible: true, _type: 'AptcDetermination').tap do |determination|
    #     determination.bases.build(basis_kind: 'state_residency', is_satisfied: true)
    #   end
    class Determination
      include Mongoid::Document
      include Mongoid::Timestamps

      embedded_in :eligibility, class_name: 'Eligibilities::V3::Eligibility'

      # @!attribute bases
      #   @return [Array<Eligibilities::V3::Basis>] Collection of basis that must be satisfied for eligibility
      embeds_many :bases, class_name: 'Eligibilities::V3::Basis', cascade_callbacks: true

      # @!attribute is_eligible
      #   @return [Boolean] Whether the applicant is eligible based on all bases being satisfied
      field :is_eligible, type: Boolean, default: false

      validates :is_eligible, presence: true
      validate :unique_basis_kinds

      private

      # @!attribute unique_basis_kinds
      #   @return [Boolean] Whether the basis kinds are unique
      def unique_basis_kinds
        embedded_basis_kinds = bases.map(&:basis_kind)
        errors.add(:bases, "Duplicate basis kinds") if embedded_basis_kinds.uniq.length != embedded_basis_kinds.length
      end
    end
  end
end
