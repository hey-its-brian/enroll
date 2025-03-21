# frozen_string_literal: true

module Adapters
  # Provides a unified interface for different types of verification evidences.
  #
  # The EvidenceAdapter normalizes access to evidence data from different sources:
  # * Primarily, `Eligibilities:EvidenceState`s under a family's eligibility determination, which itself is derived from both:
  #   - `VerificationType`
  #   - `Eligibility::Evidence`
  # * And, Identity verification information from `Person` records
  #
  # This adapter implements the Adapter pattern to present a consistent interface to views
  # and controllers, hiding the underlying differences in data structures. It uses delegation
  # to specialized delegate classes that handle the specifics of each evidence type.
  #
  # @see EligibilityEvidenceDelegate Handles eligibility evidence states
  # @see IdentityEvidenceDelegate Handles identity verification
  class EvidenceAdapter

    INTERFACE_CONTRACT = %i[
      person
      evidence_gid
      evidence_group
      evidence_item_key
      status
      due_on
      documents
      is_action_needed?
      update_reason
      history
      history_tracks
    ].freeze

    INTERFACE_CONTRACT.each do |method|
      define_method(method) do
        @delegate.send(method)
      end
    end

    def initialize(evidence)
      case evidence
      when Eligibilities::EvidenceState
        @delegate = EligibilityEvidenceDelegate.new(evidence)
      when Person
        @delegate = IdentityEvidenceDelegate.new(evidence)
      else
        raise ArgumentError, "Unsupported evidence type: #{evidence.class}"
      end
    end

    # Adapts a Person into a verification evidence interface for identity verification.
    # It creates a synthetic evidence representation with appropriate values for status,
    # documents, and other required fields, which allows identity verification to be treated consistently with other
    # verification types in view and controller layers.
    #
    # @see EvidenceAdapter The public interface that uses this delegate
    class IdentityEvidenceDelegate
      include VerificationHelper

      attr_reader :person, :evidence_group, :evidence_item_key, :status, :due_on, :update_reason,
                  :history, :history_tracks, :documents

      def initialize(person)
        @person = person
        @evidence_group = 'ridp'
        @evidence_item_key = :identity
        @status = 'valid'
        @due_on = nil
        @documents = ridp_documents_list(person, 'Identity')
        @update_reason = nil
        @history = []
        @history_tracks = nil
      end

      def is_action_needed?
        false
      end
    end

    # Adapts an `Eligibilities::EvidenceState` to provide a consistent interface with additional data.
    # This delegate decorates `Eligibilities::EvidenceState` objects by retrieving additional data from
    # the underlying `VerificationType` or `Eligibilities::Evidence` models, providing access to fields
    # that aren't directly available on the `Eligibilities::EvidenceState`, such as `documents`, `history`,
    # and more specific `status` values.
    #
    # @see EvidenceAdapter The public interface which uses this delegate
    class EligibilityEvidenceDelegate < SimpleDelegator
      include FinancialAssistance::VerificationHelper

      attr_reader :person, :evidence_group, :status, :update_reason, :documents, :history, :history_tracks

      def initialize(evidence)
        super(evidence)

        specific_evidence = derive_evidences(evidence)
        @person = evidence.eligibility_state.subject.person
        @evidence_group = evidence.eligibility_state.eligibility_item_key
        @update_reason = specific_evidence.update_reason

        case specific_evidence
        when VerificationType
          @status = specific_evidence.validation_status
          @documents = specific_evidence.type_documents
          @history = specific_evidence.type_history_elements.map { |element| EvidenceHistoryDecorator.new(element) }.sort_by(&:created_at).reverse
          @history_tracks = specific_evidence.history_tracks
        when Eligibilities::Evidence
          @documents = specific_evidence.documents
          @status = evidence.status
          @history = (specific_evidence.verification_histories + specific_evidence.request_results).map { |element| EvidenceHistoryDecorator.new(element) }.sort_by(&:created_at).reverse
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
  end
end
