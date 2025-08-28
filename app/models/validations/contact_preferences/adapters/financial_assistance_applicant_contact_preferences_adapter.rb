# frozen_string_literal: true

module Validations
  module ContactPreferences
    module Adapters
      # Adapter for FinancialAssistance::Applicant model
      class FinancialAssistanceApplicantContactPreferencesAdapter < Validations::ContactPreferences::Adapters::ContactPreferencesAdapter
        def mobile_phone
          @record.mobile_phone
        end

        def home_email
          @record.home_email
        end

        def contact_method_value
          @record.contact_method
        end

        def contact_method_options
          value = contact_method_value
          return [] if value.blank?
          FinancialAssistance::Applicant::CONTACT_METHOD_MAPPING.invert[value] || []
        end
      end
    end
  end
end
