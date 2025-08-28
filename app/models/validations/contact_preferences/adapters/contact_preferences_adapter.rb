# frozen_string_literal: true

module Validations
  module ContactPreferences
    module Adapters
      # Base adapter for contact info access
      class ContactPreferencesAdapter
        def initialize(record)
          @record = record
        end

        def mobile_phone
          raise NotImplementedError
        end

        def home_email
          raise NotImplementedError
        end

        def contact_method_value
          raise NotImplementedError
        end

        def contact_method_options
          raise NotImplementedError
        end
      end
    end
  end
end
