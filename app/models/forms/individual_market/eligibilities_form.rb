# frozen_string_literal: true

module Forms
  module IndividualMarket
    # Form for managing eligibilities information for an applicant
    class EligibilitiesForm
      include ActiveModel::Model

      attr_accessor :key, :title

      validates :key, presence: true

      def to_h
        {
          key: key&.to_sym,
          title: title
        }.compact
      end
    end
  end
end