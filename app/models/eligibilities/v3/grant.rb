# frozen_string_literal: true

module Eligibilities
  module V3
    # A grant is a financial award that is disbursed to a person or entity for a specific purpose.
    # A placeholder model for now, might not be used in the current implementation.
    class Grant
      include Mongoid::Document
      include Mongoid::Timestamps

      # Not sure if we need to embed this in eligibility only or in other models as well.
      # embedded_in :grantable, polymorphic: true
      # embedded_in :eligibility, class_name: '::Eligibilities::V3::Eligibility'

      field :title, type: String
      field :key, type: String
      field :value, type: String
    end
  end
end
