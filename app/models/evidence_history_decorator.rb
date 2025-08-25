# frozen_string_literal: true

# Represents the history of both an `Eligibilities::Evidence` and a `VerificationType` in a common interface for the `verification_history` view.
class EvidenceHistoryDecorator < SimpleDelegator
  include L10nHelper
  include VerificationHelper

  attr_reader :action, :modifier_id, :update_reason, :date_of_action, :payload

  def initialize(obj)
    super(obj)
    case obj
    when TypeHistoryElement
      @action = obj.action
      @modifier_id = obj.modifier
      @update_reason = obj.update_reason
      @date_of_action = obj.created_at
      verification_type = obj.verification_type
      @payload = request_response_details_formatted(verification_type.person, obj, verification_type.type_name) if obj.event_request_record_id.present? || obj.event_response_record_id.present?
    when Eligibilities::RequestResult, Eligibilities::V3::RequestResult
      @action = obj.action || l10n('hub_call')
      @modifier_id = determine_modifier_id(obj)
      @update_reason = l10n('fdsh_hub_call')
      @date_of_action = obj.date_of_action
      @payload = parsable_json?(obj.raw_payload) ? JSON.parse(obj.raw_payload) : obj.raw_payload if obj.raw_payload.present?
    when Eligibilities::VerificationHistory, Eligibilities::V3::VerificationHistory
      @action = obj.action
      @modifier_id = obj.updated_by
      @update_reason = obj.update_reason
      @date_of_action = obj.date_of_action
      @payload = nil
    end
  end

  private

  def parsable_json?(payload)
    JSON.parse(payload)
  rescue JSON::ParserError, TypeError => _e
    false
  end

  # Determines the modifier ID for the evidence history record.
  # For verification types, we use source_transaction_id as the primary identifier,
  # falling back to updated_by for legacy data compatibility.
  #
  # @note This conditional logic ensures a consistent interface for the view layer
  #   and maintains compatibility with Pre-QHP data migration scenarios.
  # @deprecated The updated_by field should not be used for new data implementations.
  #   Once the feature is fully implemented and legacy data is migrated, this fallback
  #   should be removed.
  # @example
  #   # New data (preferred)
  #   obj.source_transaction_id = "txn_12345"
  #   # Legacy data (deprecated)
  #   obj.updated_by = "system"
  def determine_modifier_id(obj)
    case obj
    when Eligibilities::V3::RequestResult
      obj.source_transaction_id.present? ? obj.source_transaction_id : obj.updated_by
    when Eligibilities::RequestResult
      obj.source_transaction_id
    end
  end
end
