# frozen_string_literal: true

# Concern for validating name fields in models and forms
module NameValidatable
  extend ActiveSupport::Concern

  VALID_NAME_REGEX = /\A[a-zA-Z\s'-]+\z/

  class_methods do
    def validates_name_format(*fields, **options)
      validates(*fields, format: {
        with: VALID_NAME_REGEX,
        message: "can only contain letters, spaces, hyphens, and apostrophes.",
        allow_blank: true
      }.merge(options))
    end
  end
end
