# frozen_string_literal: true

# Wrapper around an `EvidenceState` which a) exposes fields specific to `Evidence` and `VerificationType` and b) provides a common interface for the families/verification views.
# # For `Eligibilities::Evidence`:
#  1. the `documents`` field is missing.
#  2. the `verification_histories` field is missing.
# For `VerificationType`:
#  1. the `status` field loses specifcity from `validation_status`, as only "pending", "unverified", "negative_response_received", and "review" persist.
#  All other statuses are mapped to to either `:determined` or `:verified` (see `Eligibilities::Visitors::AcaIndividualMarketEligibilityVisitor`).
#  2. the `update_reason` field is missing.
#  3. the `documents` field is missing.
#  4. the `history_tracks` and `type_history_elements` fields are missing.
class EvidenceStateDecorator < SimpleDelegator
  include FinancialAssistance::VerificationHelper

  attr_reader :status, :update_reason, :documents, :history, :history_tracks

  def initialize(obj)
    super(obj)
    specific_evidence = derive_evidences(obj)
    @update_reason = specific_evidence.update_reason
    case specific_evidence
    when VerificationType
      @status = specific_evidence.validation_status
      @documents = specific_evidence.type_documents
      @history = specific_evidence.type_history_elements
      @history_tracks = specific_evidence.history_tracks
    when Eligibilities::Evidence
      @documents = specific_evidence.documents
      @status = obj.status
      @history = specific_evidence.verification_histories
      @history_tracks = nil
    end
  end

  private

  def derive_evidences(evidence)
    parsed = GlobalID.parse(evidence.evidence_gid)
    if parsed.model_class == VerificationType
      evidence.eligibility_state.subject.person.verification_types.where(id: parsed.model_id).first
    else
      family = evidence.eligibility_state.subject.determination.determinable
      application = fetch_latest_determined_application(family)
      applicant = application.applicants.where(family_member_id: GlobalID.parse(evidence.eligibility_state.subject.gid).model_id).first
      applicant.fetch_evidence(evidence.evidence_item_key.to_s)
    end
  end
end