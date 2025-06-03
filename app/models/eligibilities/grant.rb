# frozen_string_literal: true

module Eligibilities
  # Stores Tax household level information for APTC & csr value for CSR type grants.
  class Grant
    include Mongoid::Document
    include Mongoid::Timestamps

    # Keys for all types of grants supported in the system. For now all the Grants we have are for Individual Market.
    KEYS = ['AdvancePremiumAdjustmentGrant', 'CsrAdjustmentGrant', 'MagiMedicaidGrant', 'QhpGrant'].freeze

    field :title, type: String
    field :key, type: String
    field :value, type: String
    field :start_on, type: Date
    field :end_on, type: Date
    field :assistance_year, type: Integer
    field :member_ids, type: Array
    field :tax_household_group_id, type: String
    field :tax_household_id, type: String

    embedded_in :determination, class_name: "::Eligibilities::Determination"
    embedded_in :eligibility_state, class_name: "::Eligibilities::EligibilityState"

    scope :by_year, ->(year) { where(assistance_year: year) }
    scope :aptc_qhp_magi_grants, -> { where(:key.in => %w[AdvancePremiumAdjustmentGrant QhpGrant MagiMedicaidGrant]) }
    scope :by_key, ->(key) { where(key: key) }
  end
end
