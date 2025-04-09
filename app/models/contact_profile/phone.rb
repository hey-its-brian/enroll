# frozen_string_literal: true

module ContactProfile
  # Represents a phone record within a contact's details
  #
  # @note This class is embedded within the ContactDetail model as part of a
  #   'embeds_many' relationship. This design allows the system to track
  #   the history of multiple versions of phones over time.
  class Phone
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [r] contact_detail
    #   @return [ContactProfile::ContactDetail] The parent contact detail this phone belongs to
    embedded_in :contact_detail, class_name: 'ContactProfile::ContactDetail'

    # @!attribute [rw] mobile_phone
    #   @return [ContactProfile::MobilePhone] The embedded mobile phone details
    embeds_one :mobile_phone, class_name: 'ContactProfile::MobilePhone'

    # @!attribute [rw] work_phone
    #   @return [ContactProfile::WorkPhone] The embedded work phone details
    embeds_one :work_phone, class_name: 'ContactProfile::WorkPhone'

    # @!scope class
    # @return [Mongoid::Criteria] The most recent Phone based on creation timestamp
    scope :newest, -> { order_by(created_at: :desc).limit(1) }
  end
end
