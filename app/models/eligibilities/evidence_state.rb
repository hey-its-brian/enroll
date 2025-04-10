# frozen_string_literal: true

module Eligibilities
  # Evidence State model
  class EvidenceState
    include Mongoid::Document
    include Mongoid::Timestamps

    SOCIAL_SECURITY_NUMBER = :social_secruity_number
    AMERICAN_INDIAN_STATUS = :american_indian_status
    CITIZENSHIP = :citizenship
    IMMIGRATION_STATUS = :immigration_status
    ALIVE_STATUS = :alive_status
    LOCATION_RESIDENCY = :residency

    ALL_VERIFICATION_TYPES = [
      SOCIAL_SECURITY_NUMBER,
      AMERICAN_INDIAN_STATUS,
      CITIZENSHIP,
      IMMIGRATION_STATUS,
      ALIVE_STATUS
    ].freeze

    ALL_VERIFICATION_TYPES += [LOCATION_RESIDENCY] if EnrollRegistry.feature_enabled?(:location_residency_verification_type)
    ADMIN_CALL_HUB_VERIFICATION_TYPES = ALL_VERIFICATION_TYPES - [ALIVE_STATUS, AMERICAN_INDIAN_STATUS].freeze

    embedded_in :eligibility_state, class_name: '::Eligibilities::EligibilityState'

    field :evidence_item_key, type: Symbol
    field :evidence_gid, type: String
    field :subject_gid, type: String
    field :status, type: Symbol
    field :is_satisfied, type: Boolean
    field :verification_outstanding, type: Boolean
    field :due_on, type: Date
    field :visited_at, type: DateTime
    field :meta, type: Hash

    scope :by_key, ->(key) { where(evidence_item_key: key.to_sym) }

    def is_action_needed?
      grouped_status == :action_needed
    end

    def grouped_status
      return :action_needed if verification_outstanding && status.to_s.downcase != 'review'
      return :review if status.to_s.downcase == 'review'

      :verified
    end

    # seliarizable_cv_hash for evidence states
    # @return [Hash] hash of evidence states
    def serializable_cv_hash
      evidence_state_attributes = attributes.except("_id", "updated_at", "created_at", "visited_at", "evidence_gid")
      evidence_state_attributes[:visited_at] = visited_at
      evidence_state_attributes[:evidence_gid] = URI(evidence_gid).to_s

      evidence_state_attributes
    end

    # Locates the referenced evidence item.
    # This method is a workaround for the fact that GlobalID does not provide a way to locate embedded documents.
    # @return [Object] The referenced evidence object if found, otherwise nil.
    def locate_evidence
      parsed = GlobalID.parse(evidence_gid)
      model_id = parsed.model_id
      person = eligibility_state.subject.person
      family_id = eligibility_state.subject.determination.determinable.id
      case parsed.model_class
      when VerificationType
        person.verification_types.where(id: model_id).first
      when Eligibilities::Evidence
        determined_apps = ::FinancialAssistance::Application.where(family_id: family_id).determined
        family_member_id = Family.find(family_id).family_members.where(person_id: person).first.id
        applicant_for_apps = determined_apps.map { |app| app.applicants.where(family_member_id: family_member_id).first }.compact
        evidences_for_applicant = applicant_for_apps.map { |applicant| applicant.fetch_evidence(evidence_item_key.to_s) }.compact
        evidences_for_applicant.detect { |ev| ev.id.to_s == model_id }
      end
    end
  end
end
