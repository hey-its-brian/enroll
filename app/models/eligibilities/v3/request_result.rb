# frozen_string_literal: true

module Eligibilities
  module V3
    # Stores all the results we received from the external services.
    class RequestResult
      include Mongoid::Document
      include Mongoid::Timestamps

      embedded_in :evidence, class_name: '::Eligibilities::V3::Evidence'

      field :result, type: String
      field :source, type: String
      field :source_transaction_id, type: String
      field :code, type: String
      field :code_description, type: String
      field :raw_payload, type: String
      field :date_of_action, type: DateTime
      field :action, type: String

      # @!attribute updated_by
      #   @return [String] The identifier of the entity that last updated this record
      #   @deprecated This field is used only for migrated legacy data compatibility
      #   @note For verification types, we migrate values from type history elements to request results
      #     to maintain a consistent interface for the view layer. This field replaces the use of
      #     source_transaction_id for pre-QHP data migration scenarios.
      #   @see source_transaction_id For new implementations, use source_transaction_id instead
      #   @example Legacy data migration
      #     request_result.updated_by = "system"
      field :updated_by, type: String

      before_create :set_date_of_action, unless: -> { date_of_action.present? }

      private

      def set_date_of_action
        self.date_of_action = DateTime.now
      end
    end
  end
end
