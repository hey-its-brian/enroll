# frozen_string_literal: true

class Email
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::History::Trackable

  include Validations::Email

  embedded_in :person
  embedded_in :office_location
  embedded_in :census_member, class_name: "CensusMember"
  embedded_in :applicant, class_name: "IndividualMarket::Applicant"

  KINDS = %w[home work].freeze

  field :kind, type: String
  field :address, type: String

  track_history :on => [:fields],
                :scope => :person,
                :modifier_field => :modifier,
                :modifier_field_optional => true,
                :version_field => :tracking_version,
                :track_create => true,    # track document creation, default is false
                :track_update => true,    # track document updates, default is true
                :track_destroy => true

  validates :address, :email => true, :allow_blank => false
  validates_presence_of  :kind, message: "Choose a type"
  validates_inclusion_of :kind, in: KINDS, message: "%{value} is not a valid email type"

  VALID_EMAIL_REGEX = %r{\A[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]+)*@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+\z}i

  validates :address,
            presence: true,
            format: {
              :with => VALID_EMAIL_REGEX,
              :message => "should be a valid email address"
            }

  def blank?
    address.blank?
  end

  def match(another_email)
    return false if another_email.nil?
    attrs_to_match = [:kind, :address]
    attrs_to_match.all? { |attr| attribute_matches?(attr, another_email) }
  end

  def attribute_matches?(attribute, other)
    self[attribute] == other[attribute]
  end

end
