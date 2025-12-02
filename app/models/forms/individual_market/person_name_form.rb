# frozen_string_literal: true

module Forms
  module IndividualMarket
    # Form for managing person name information for an applicant
    class PersonNameForm
      include ActiveModel::Model
      include ActiveModel::Validations
      include NameValidatable

      attr_accessor :id,
                    :given_name,
                    :family_name,
                    :middle_name,
                    :name_pfx,
                    :name_sfx,
                    :alternate_name

      validates :given_name, :family_name, presence: true
      validates_name_format :given_name, :family_name, :middle_name
      validate :suffix_validation

      def initialize(attributes = {})
        super
      end

      def to_h
        {
          given_name: given_name,
          family_name: family_name,
          middle_name: middle_name,
          name_pfx: name_pfx,
          name_sfx: name_sfx,
          alternate_name: alternate_name
        }.compact
      end

      def persisted?
        id.present?
      end

      private

      def suffix_validation
        return true unless name_sfx.present?
        errors.add(:name_sfx, "is not a valid suffix") unless ::PersonName::SUFFIX_OPTIONS.include?(name_sfx)
      end
    end
  end
end