# frozen_string_literal: true

# Helper methods for building the shared `contact_preferences_fields` partial.
#
# This helper abstracts the complexity of different data models that store
# contact preferences in different ways:
# - Some objects (like Person) store preferences in nested child documents
# - Others (like Applicant) store preferences directly on themselves
#
# The helper provides a unified interface for the view to work with both patterns.
module ContactPreferencesHelper
  # Maps object class names to the nested field that contains their contact preferences.
  # Classes not listed here are assumed to store preferences directly.
  PREFERENCE_FIELD_MAPPING = { 'Person' => :consumer_role }.freeze

  # Generates configuration for the contact preferences form based on the form object type.
  #
  # @param form_builder [ActionView::Helpers::FormBuilder] The form builder instance
  # @return [Hash] Configuration hash containing:
  #   - :contact_object - The object containing phone/email data
  #   - :form_builder - The original form builder
  #   - :preferences_field - The nested field name (if any) containing preferences
  def contact_preferences_fields_config(form_builder)
    config = { contact_object: form_builder.object, form_builder: form_builder }
    config[:preferences_field] = PREFERENCE_FIELD_MAPPING[form_builder.object.class.name]
    config
  end

  # Conditionally wraps form fields in a nested fields_for block based on the object type.
  #
  # For objects with nested preference fields (like Person), this creates a fields_for
  # block targeting the nested document. For objects with direct preferences (like Applicant),
  # it yields the original form builder directly.
  #
  # @param config [Hash] Configuration from contact_preferences_fields_config
  # @yield [form_builder] The appropriate form builder for preference fields
  def with_preferences_form(config, &block)
    if config[:preferences_field]
      config[:form_builder].fields_for config[:preferences_field], errors: {}, fieldset: true, &block
    else
      capture(config[:form_builder], &block)
    end
  end
end
