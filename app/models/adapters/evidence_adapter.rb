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
  # @see EligibilityEvidenceStateDelegate Handles eligibility evidence states
  # @see IdentityEvidenceDelegate Handles identity verification
  # @see VerificationTypeDelegate Handles verification types
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
      grouped_status
      update_reason
      history
      history_tracks
      inactive
      detail_params
      locate_evidence
    ].freeze

    INTERFACE_CONTRACT.each do |method|
      define_method(method) do
        @delegate.send(method)
      end
    end

    def initialize(evidence)
      @delegate = EvidenceAdapterFactory.for(evidence)
    end

    def detail_params
      { person_id: person.id, eligibility_kind: evidence_group, evidence_key: evidence_item_key, inactive: inactive }
    end

    # Creates an appropriate delegate based on the type of evidence provided.
    class EvidenceAdapterFactory
      def self.for(evidence)
        case evidence
        when VerificationType
          Delegates::VerificationTypeDelegate.new(evidence)
        when Eligibilities::EvidenceState
          Delegates::EligibilityEvidenceStateDelegate.new(evidence)
        when Person
          Delegates::IdentityEvidenceDelegate.new(evidence)
        else
          raise ArgumentError, "Unsupported evidence type: #{evidence.class}"
        end
      end
    end

    module Delegates
      # Helper module to format history elements.
      module HistoryHelper
        def format_history(elements)
          Array(elements).map { |element| EvidenceHistoryDecorator.new(element) }
                         .sort_by(&:created_at)
                         .reverse
        end
      end

      # Adapts a `VerificationType` into a verification evidence interface.
      #
      # @see EvidenceAdapter The public interface that uses this delegate
      class VerificationTypeDelegate
        include HistoryHelper

        attr_reader :person, :evidence_group, :evidence_item_key, :status, :due_on, :update_reason, :history, :history_tracks, :documents, :inactive

        def initialize(verification_type)
          @person = verification_type.person
          @evidence_group = 'aca_individual_market_eligibility'
          @evidence_item_key = verification_type.type_name.downcase.to_sym
          @status = verification_type.validation_status
          @due_on = verification_type.due_date
          @documents = verification_type.type_documents
          @update_reason = nil
          @history = format_history(verification_type.type_history_elements)
          @history_tracks = verification_type.history_tracks
          @inactive = verification_type.inactive # all VerificationTypeDelegates should be inactive
        end

        def is_action_needed?
          false
        end

        def grouped_status
          :verified
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
                    :history, :history_tracks, :documents, :inactive

        def initialize(person)
          @person = person
          @evidence_group = 'ridp'
          @evidence_item_key = :identity
          @status = 'valid'
          @due_on = nil
          @documents = ridp_documents_list(person, 'Identity') + ridp_documents_list(person, 'Application')
          @update_reason = nil
          @history = []
          @history_tracks = nil
          @inactive = false
        end

        def is_action_needed?
          false
        end

        def grouped_status
          :verified
        end
      end

      # Adapts an `Eligibilities::EvidenceState` to provide a consistent interface with additional data.
      # This delegate decorates `Eligibilities::EvidenceState` objects by retrieving additional data from
      # the underlying `VerificationType` or `Eligibilities::Evidence` models, providing access to fields
      # that aren't directly available on the `Eligibilities::EvidenceState`, such as `documents`, `history`,
      # and more specific `status` values.
      #
      # @see EvidenceAdapter The public interface which uses this delegate
      class EligibilityEvidenceStateDelegate < SimpleDelegator
        include FinancialAssistance::VerificationHelper
        include HistoryHelper

        attr_reader :person, :evidence_group, :status, :update_reason, :documents, :history, :history_tracks, :inactive

        def initialize(evidence)
          super(evidence)

          specific_evidence = evidence.locate_evidence
          @person = evidence.eligibility_state.subject.person
          @evidence_group = evidence.eligibility_state.eligibility_item_key
          @update_reason = specific_evidence.update_reason
          @inactive = false

          case specific_evidence
          when VerificationType
            @status = specific_evidence.validation_status
            @documents = specific_evidence.type_documents
            @history = format_history(specific_evidence.type_history_elements)
            @history_tracks = specific_evidence.history_tracks
          when Eligibilities::Evidence
            @documents = specific_evidence.documents
            @status = evidence.status
            @history = format_history(specific_evidence.verification_histories + specific_evidence.request_results)
            @history_tracks = nil
          end
        end
      end
    end
  end
end
