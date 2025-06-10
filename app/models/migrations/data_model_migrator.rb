# frozen_string_literal: true

module Migrations
  # Handles the migration of data from an old model to a new model.
  # This class maps fields between models and supports nested attributes.
  class DataModelMigrator
    # Initializes the migrator
    def initialize; end

    # Retrieves the field mappings for a given model name.
    #
    # @param model_name [String, Symbol] The name of the model to retrieve mappings for.
    # @return [Hash] A hash of field mappings where keys are old model fields
    #   and values are new model fields.
    def self.field_mappings(model_name)
      @field_mappings ||= load_mappings
      @field_mappings[model_name.to_s] || {}
    end

    # Loads and validates the field mappings from the configuration file.
    #
    # @return [Hash] The validated field mappings.
    # @raise [StandardError] If the mappings are invalid.
    def self.load_mappings
      file_path = Rails.root.join('app/models/migrations/mapping_config.yml')
      mappings = YAML.safe_load(File.read(file_path), permitted_classes: [Symbol])
      validate_mappings(mappings)
      mappings
    rescue Errno::ENOENT
      raise "Mapping configuration file not found at #{file_path}"
    end

    # Validates the structure of the field mappings.
    #
    # @param mappings [Hash] The field mappings to validate.
    # @raise [StandardError] If the mappings are invalid.
    def self.validate_mappings(mappings)
      raise "Invalid mappings format" unless mappings.is_a?(Hash)
    end

    # Performs the migration process.
    #
    # Maps fields from the old model to the new model based on the field mappings.
    # Handles both direct field mappings and nested attributes.
    #
    # @param old_model [Object] The old model instance.
    # @param new_model [Object] The new model instance.
    # @return [Object] The new model with migrated data.
    def perform(old_model, new_model)
      validate_models!(old_model, new_model)
      class_name = old_model.class.name.split('::').last.underscore
      mappings = self.class.field_mappings(class_name)
      mappings = self.class.field_mappings(mappings) unless mappings.is_a?(Hash)

      mappings.each do |old_field, new_field|
        migrate_field(old_model, new_model, old_field, new_field)
      end
      new_model
    end

    private

    # Validates the old and new model instances.
    #
    # @param old_model [Object] The old model instance.
    # @param new_model [Object] The new model instance.
    # @raise [ArgumentError] If the models are invalid.
    def validate_models!(old_model, new_model)
      raise ArgumentError, "Old model object must be a Mongoid Document" unless old_model.is_a?(::Mongoid::Document)
      raise ArgumentError, "New model object must be a Mongoid Document" unless new_model.is_a?(::Mongoid::Document)
    end

    # Migrates a single field from the old model to the new model.
    #
    # @param old_model [Object] The old model instance.
    # @param new_model [Object] The new model instance.
    # @param old_field [String, Symbol] The field in the old model.
    # @param new_field [String, Symbol] The field in the new model.
    def migrate_field(old_model, new_model, old_field, new_field)
      if old_field.to_s.end_with?('_attributes')
        migrate_nested_attributes(old_model, new_model, old_field, new_field)
      elsif old_model.respond_to?(old_field) && new_field.start_with?('resolve_')
        resolve_field(old_model, new_model, old_field, new_field)
      elsif old_model.respond_to?(old_field)
        new_model[new_field] = old_model[old_field]
      end
    end

    def resolve_field(old_model, new_model, old_field, resolution_key)
      resolution = self.class.field_mappings('field_resolutions')[resolution_key]
      case resolution
      when /^!(.+)/
        field_name = resolution_key.to_s.gsub('resolve_', '')
        new_model[field_name] = !old_model[old_field]
      end
    end

    # Migrates nested attributes from the old model to the new model.
    #
    # @param old_model [Object] The old model instance.
    # @param new_model [Object] The new model instance.
    # @param old_field [String, Symbol] The field in the old model.
    # @param new_field [String, Symbol] The field in the new model.
    def migrate_nested_attributes(old_model, new_model, old_field, new_field)
      nested_field = old_field.to_s.gsub('_attributes', '')
      return unless old_model.respond_to?(nested_field)

      value = resolve_nested_object(nested_field)
      looper = value.present? ? old_model.public_send(nested_field).order_by(:"#{value}".asc) : old_model.public_send(nested_field)

      looper.each do |old_nested_model|
        new_nested_model = new_model.public_send(new_field).build
        perform(old_nested_model, new_nested_model)
      end
    end

    def resolve_nested_object(resolution_key)
      self.class.field_mappings('nested_object_resolution')[resolution_key]
    end
  end
end