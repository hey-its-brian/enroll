# frozen_string_literal: true

module Forms
  module IndividualMarket
    # Form for managing immigration information for an applicant
    class ImmigrationInformationForm
      include ActiveModel::Model

      attr_accessor :subject,
                    :alien_number,
                    :i94_number,
                    :visa_number,
                    :passport_number,
                    :sevis_id,
                    :naturalization_number,
                    :receipt_number,
                    :citizenship_number,
                    :card_number,
                    :country_of_citizenship,
                    :expiration_date,
                    :issuing_country,
                    :description,
                    :immigration_doc_statuses,
                    :id

      validate :allowed_subject

      def initialize(attributes = {})
        super
        self.immigration_doc_statuses = immigration_doc_statuses&.compact_blank
        self.subject = sanitize_subject
      end

      def to_h
        {
          subject: subject,
          alien_number: alien_number,
          i94_number: i94_number,
          visa_number: visa_number,
          passport_number: passport_number,
          sevis_id: sevis_id,
          naturalization_number: naturalization_number,
          receipt_number: receipt_number,
          citizenship_number: citizenship_number,
          card_number: card_number,
          country_of_citizenship: country_of_citizenship,
          expiration_date: expiration_date,
          issuing_country: issuing_country,
          description: description,
          immigration_doc_statuses: immigration_doc_statuses
        }.compact
      end

      private

      def sanitize_subject
        return nil if subject.blank?
        return nil if subject.to_s.downcase == "select document type"
        subject&.strip
      end

      def allowed_subject
        return unless subject.present?
        allowed_subjects = VlpDocument::NATURALIZATION_DOCUMENT_TYPES + VlpDocument::VLP_DOCUMENT_KINDS
        errors.add(:subject, "must be one of #{allowed_subjects.join(', ')}") unless allowed_subjects.include?(subject)
      end
    end
  end
end