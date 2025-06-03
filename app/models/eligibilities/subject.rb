# frozen_string_literal: true

module Eligibilities
  # Subject
  class Subject
    include Mongoid::Document
    include Mongoid::Timestamps

    embedded_in :determination, class_name: "::Eligibilities::Determination"
    embeds_many :eligibility_states, class_name: "::Eligibilities::EligibilityState", cascade_callbacks: true

    field :gid, type: String
    field :first_name, type: String
    field :last_name, type: String
    field :full_name, type: String
    field :is_primary, type: Boolean
    field :hbx_id, type: String
    field :person_id, type: String
    field :encrypted_ssn, type: String
    field :dob, type: Date
    field :outstanding_verification_status, type: String

    accepts_nested_attributes_for :eligibility_states

    scope :by_person, ->(id) { where(person_id: id) }

    before_save :add_full_name

    def add_full_name
      self.full_name = [first_name, last_name].join(' ')
    end

    def csr_by_year(year)
      eligibility_state = eligibility_states.where(eligibility_item_key: 'aptc_csr_credit').first
      grant = eligibility_state.grants.where(key: 'CsrAdjustmentGrant', assistance_year: year).first

      grant&.value
    end

    def person
      ::Person.find(person_id)
    end

    def outstanding?
      outstanding_verification_status == 'outstanding'
    end

    def aptc_csr_eligibility_state
      eligibility_states.by_type('aptc_csr_credit').first
    end

    def magi_medicaid_grant_by_year(year)
      aptc_csr_eligibility_state&.magi_medicaid_grant_by_year(year)
    end

    def is_active?
      family_member = GlobalID::Locator.locate(gid)
      raise "Family member not found" unless family_member

      family_member.is_active
    end

    def earliest_due_date
      eligibility_states.by_type_uploadable.collect(&:earliest_due_date).compact.min
    end

    def documents_action_needed?
      cumulative_grouped_status == :action_needed
    end

    def cumulative_grouped_status
      uploadable_eligibility_states = eligibility_states.by_type_uploadable
      return :action_needed if uploadable_eligibility_states.any? { |es| es.cumulative_grouped_status == :action_needed }
      return :review if uploadable_eligibility_states.any? { |es| es.cumulative_grouped_status == :review }

      :verified
    end

    # seliarizable_cv_hash for subject including eligibility states
    # @return [Hash] hash of subject
    def serializable_cv_hash
      eligibility_states_hash = eligibility_states.collect do |eligibility_state|
        Hash[
          eligibility_state.eligibility_item_key,
          eligibility_state.serializable_cv_hash
        ]
      end.reduce(:merge)

      subject_attributes = attributes.symbolize_keys.slice(:first_name, :last_name, :encrypted_ssn, :hbx_id, :person_id, :is_primary, :outstanding_verification_status)

      if subject_attributes[:encrypted_ssn].present?
        encrypted_ssn = AcaEntities::Operations::Encryption::Encrypt.new.call(value: SymmetricEncryption.decrypt(subject_attributes[:encrypted_ssn])).value! # For CV3 payload
        subject_attributes[:encrypted_ssn] = encrypted_ssn
      end

      subject_attributes[:dob] = dob
      subject_attributes[:eligibility_states] = eligibility_states_hash

      subject_attributes
    end
  end
end

