# frozen_string_literal: true

module ContactProfile
  # Represents a phone number on the blocklist.
  class BlockedPhoneNumber
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mongoid::History::Trackable

    track_history :modifier_field => :modifier,
                  :modifier_field_optional => true,
                  :version_field => :tracking_version,
                  :track_create => true,    # track document creation, default is false
                  :track_update => true,    # track document updates, default is true
                  :track_destroy => true

    # @!attribute [rw] phone number
    #   @return [String] The normalized phone number.
    field :number, type: String

    index({:number => 1})
  end
end