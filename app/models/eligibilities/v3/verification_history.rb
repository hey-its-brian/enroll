# frozen_string_literal: true

module Eligibilities
  module V3
    # Stores the history of each transaction a user, admin, or automated process has performed on an evidence
    class VerificationHistory
      include Mongoid::Document
      include Mongoid::Timestamps

      embedded_in :evidence, class_name: '::Eligibilities::V3::Evidence'

      field :action, type: String
      field :update_reason, type: String
      field :updated_by, type: String
      field :is_satisfied, type: Boolean
      field :verification_outstanding, type: Boolean
      # @!attribute [rw] due_on
      #   @return [Date] The `due_on` date of the evidence at the time this verification history record was created.
      #
      #   @note When a due date no longer applies (e.g., evidence is verified or enters nrr state), the evidence's `due_on` field may be set to nil.
      #         However, sometimes we may later need to restore the original due date (e.g., if evidence is rejected after being verified).
      #         To support this, we retain the last known due date whenever recording a verification history entry.
      #   @note See `Eligibilities::V3::EvidenceUtils#build_verification_history` for registering verification history entries.
      #   @note See `Eligibilities::V3::EvidenceUtils#most_recent_due_on` for retrieving the most recent due date from history.
      field :due_on, type: Date

      # Need to verify if this field is necessary, as we do not copy the verification histories between applications to retain this information.
      # This field is previously used to retain the timestamp of when the verification history object was created on the first application.
      # To present the date of the action, instead of modifying the created_at field, we used this field.
      field :date_of_action, type: DateTime

      # @!scope class
      # @return [Mongoid::Criteria] All VerificationHistory records with a due date set
      scope :with_due_date, -> { where(:due_on.ne => nil) }

      # @!scope class
      # @return [Mongoid::Criteria] The most recent VerificationHistory based on creation timestamp
      # @note Uses limit(1) to optimize query performance by instructing MongoDB to stop
      #   after finding the first matching record, reducing database load and network transfer.
      #   Without this limit, MongoDB would retrieve and sort all records unnecessarily.
      scope :newest,      -> { order_by(created_at: :desc).limit(1) }

      before_create :set_date_of_action, unless: -> { date_of_action.present? }

      private

      def set_date_of_action
        self.date_of_action = DateTime.now
      end
    end
  end
end
