# frozen_string_literal: true

module Eligibilities
  module V3
    # Stores the history of each transaction a user or admin has performed on an evidence
    class VerificationHistory
      include Mongoid::Document
      include Mongoid::Timestamps

      embedded_in :evidence, class_name: '::Eligibilities::V3::Evidence'

      field :action, type: String
      field :modifier, type: String
      field :update_reason, type: String
      field :updated_by, type: String
      field :is_satisfied, type: Boolean
      field :verification_outstanding, type: Boolean
      field :due_on, type: Date
      field :aasm_state, type: String
      field :date_of_action, type: DateTime

      before_create :set_date_of_action, unless: -> { date_of_action.present? }

      private

      def set_date_of_action
        # write_attribute(:date_of_action, DateTime.now)
        self.date_of_action = DateTime.now
      end
    end
  end
end
