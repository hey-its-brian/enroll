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
      field :due_on, type: Date
      field :date_of_action, type: DateTime

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
