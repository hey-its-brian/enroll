# frozen_string_literal: true

module Eligibilities
  # Evidence State model
  class EvidenceState
    include Mongoid::Document
    include Mongoid::Timestamps
    include ResourceRegistryHelper

    SOCIAL_SECURITY_NUMBER = :social_security_number
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
      return :action_needed if ['outstanding', 'rejected'].include?(status.to_s.downcase)
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

    # Retrieves evidence object using the Global ID from evidence_state.
    # Uses either QHP or class-based lookup depending on configuration.
    #
    # @return [Object] The located evidence object
    def locate_evidence
      parsed_gid = GlobalID.parse(evidence_gid)
      model_id = parsed_gid.model_id
      person, family_member_id, family_id, determination = determine_person_family

      if qhp_application_feature_enabled?
        locate_evidence_by_qhp(determination, family_member_id, model_id)
      else
        locate_evidence_by_class(parsed_gid, model_id, person, family_id)
      end
    end

    private

    # Identifies and determines person/family details associated with the evidence item.
    # @return [Array] [person, family_member_id, family_id, determination]
    def determine_person_family
      subject = eligibility_state.subject
      person = subject.person
      determination = subject.determination
      family = determination.determinable
      family_member = family.family_members.where(person_id: person).first
      [person, family_member.id, family.id, determination]
    end

    # Locates evidence in applications identified by QHP (Qualified Health Plan) specific logic.
    # @param determination [Object] The determination object containing family context.
    # @param family_member_id [String] The ID of the family member related to the evidence.
    # @param model_id [String] The ID of the model evidence.
    # @return [Object, nil] The found evidence object or nil if not found.
    def locate_evidence_by_qhp(determination, family_member_id, model_id)
      application = GlobalID::Locator.locate(determination.application_gid)
      applicant = application.applicants.where(family_member_id: family_member_id).first
      applicant.eligibilities.flat_map(&:evidences).detect { |evidence| evidence.id.to_s == model_id }
    end

    # Handles locating evidence based on its class (e.g., `VerificationType` or `Eligibilities::Evidence`).
    # @param parsed_gid [Object] Parsed GlobalID object containing a model class and ID.
    # @param model_id [String] The ID of the model evidence.
    # @param person [Object] The person associated with the evidence.
    # @param family_id [String] The ID of the family associated with the person.
    # @return [Object, nil] The located evidence object or nil if not found.
    def locate_evidence_by_class(parsed_gid, model_id, person, family_id)
      case parsed_gid.model_class
      when VerificationType
        person.verification_types.where(id: model_id).first
      when Eligibilities::Evidence
        locate_evidence_from_determined_apps(family_id, person.id, model_id)
      end
    end

    # Searches determined applications for eligible evidence tied to the given model and family member.
    # @param family_id [String] The ID of the family in the context.
    # @param person_id [String] The ID of the person associated with the evidence.
    # @param model_id [String] The ID of the model evidence.
    # @return [Object, nil] The matched evidence object or nil if not found.
    def locate_evidence_from_determined_apps(family_id, person_id, model_id)
      determined_apps = ::FinancialAssistance::Application.where(family_id: family_id).determined
      family_member_id = Family.find(family_id).family_members.where(person_id: person_id).first.id
      applicants = determined_apps.map { |app| app.applicants.where(family_member_id: family_member_id).first }.compact
      evidences = applicants.map { |applicant| applicant.fetch_evidence(evidence_item_key.to_s) }.compact
      evidences.detect { |evidence| evidence.id.to_s == model_id }
    end
  end
end
