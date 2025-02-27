# frozen_string_literal: true

# Represents the history of both an `Eligibilities::Evidence` and a `VerificationType` in a common interface for the `verification_history` view.
class EvidenceHistoryDecorator < SimpleDelegator
  include L10nHelper
  include VerificationHelper

  attr_reader :action, :modifier_id, :update_reason, :payload

  def initialize(obj)
    super(obj)
    case obj
    when TypeHistoryElement
      @action = obj.action
      @modifier_id = obj.modifier
      @update_reason = obj.update_reason
      verification_type = obj.verification_type
      @payload = request_response_details_formatted(verification_type.person, obj, verification_type.type_name) if obj.event_request_record_id.present? || obj.event_response_record_id.present?
    when Eligibilities::RequestResult
      @action = obj.action || l10n('hub_call')
      @modifier_id = obj.source_transaction_id
      @update_reason = l10n('fdsh_hub_call')
      @payload = JSON.parse(obj.raw_payload) if obj.raw_payload.present?
    when Eligibilities::VerificationHistory
      @action = obj.action
      @modifier_id = obj.updated_by
      @update_reason = obj.update_reason
      @payload = nil
    end
  end
end
