# frozen_string_literal: true

module Eligibilities
  # family determinaiton model
  class Determination
    include Mongoid::Document
    include Mongoid::Timestamps

    embedded_in :determinable, polymorphic: true
    embeds_many :subjects, class_name: "::Eligibilities::Subject", cascade_callbacks: true
    embeds_many :grants, class_name: "::Eligibilities::Grant", cascade_callbacks: true

    field :effective_date, type: Date
    field :outstanding_verification_status, type: String
    field :outstanding_verification_earliest_due_date, type: Date
    field :outstanding_verification_document_status, type: String

    # @!attribute application_gid
    #   @return [String] The global ID of the application associated with this determination.
    #
    # @note The application GlobalID URI is persisted for performance reasons.
    field :application_gid, type: String

    accepts_nested_attributes_for :subjects, :grants

    def subjects_action_needed?
      subjects.select(&:is_active?).any?(&:documents_action_needed?)
    end

    # seliarizable_cv_hash for family determination including subjects
    # @return [Hash] hash of family determination
    # Used in family cv3 payload
    def serializable_cv_hash
      subjects_hash = subjects.collect do |subject|
        Hash[
          URI(subject.gid).to_s,
          subject.serializable_cv_hash
        ]
      end.reduce(:merge)

      {effective_date: effective_date,
       subjects: subjects_hash,
       outstanding_verification_status: outstanding_verification_status,
       outstanding_verification_earliest_due_date: outstanding_verification_earliest_due_date,
       outstanding_verification_document_status: outstanding_verification_document_status}.deep_symbolize_keys
    end

    # Determines if a family member is eligible for Medicaid
    # @param family_member [FamilyMember] The family member to check eligibility for
    # @return [Boolean] true if the family member is eligible for Medicaid, false otherwise
    def member_medicaid_eligible?(family_member, year)
      subject = subjects.detect { |subj| subj.person_id == family_member.person.id.to_s }
      magi_medicaid_grant = subject&.magi_medicaid_grant_by_year(year)
      magi_medicaid_grant_member_ids = magi_medicaid_grant&.member_ids&.flatten&.uniq || []
      magi_medicaid_grant_member_ids.include?(family_member.id.to_s)
    end

    # APTC eligible member IDs
    def aptc_eligible_member_ids(year)
      grants.select{|grant| grant.assistance_year == year }.flat_map(&:member_ids)
    end

    # Returns an array of family member IDs that are eligible for plan shopping
    # Eligibility is determined by having eligible eligibility states (aptc_csr_credit or
    # aca_individual_market_eligibility) with qualifying grants (AdvancePremiumAdjustmentGrant,
    # QhpGrant or MagiMedicaidGrant)
    # @return [Array<String>] Array of family member IDs eligible for shopping
    def shopping_eligible_member_ids(year)
      eligible_ids = subjects.flat_map do |subject|
        # Get relevant eligibility states
        eligibility_states = subject.eligibility_states.select do |state|
          %w[aptc_csr_credit aca_individual_market_eligibility].include?(state.eligibility_item_key)
        end

        # Skip if no eligible states
        next [] if eligibility_states.empty?

        # Get member IDs from grants in eligible states
        eligibility_states.flat_map do |state|
          grants = state.grants.select do |grant|
            grant.assistance_year == year && %w[AdvancePremiumAdjustmentGrant QhpGrant MagiMedicaidGrant].include?(grant.key)
          end

          next [] if grants.empty?

          grants.flat_map(&:member_ids)
        end
      end
      # Combine with APTC eligible members and ensure uniqueness
      (eligible_ids + aptc_eligible_member_ids(year)).flatten.compact.uniq
    end
  end
end
