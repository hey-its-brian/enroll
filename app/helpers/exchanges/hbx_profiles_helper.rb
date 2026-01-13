module Exchanges
  module HbxProfilesHelper
    def get_person_roles(person, person_roles = [])
      person_roles << "Employee Role" if person.active_employee_roles.present?
      person_roles << "Consumer Role" if person.is_consumer_role_active?
      person_roles << "Resident Role" if person.is_resident_role_active?
      person_roles << "Hbx Staff Role" if person.hbx_staff_role.present?
      person_roles << "Assister Role" if person.assister_role.present?
      person_roles << "CSR Role" if person.csr_role.present?
      person_roles << "POC" if person.employer_staff_roles.present?
      person_roles << "Broker Agency Staff Role" if person.broker_agency_staff_roles.present?
      person_roles << "General Agency Staff Role" if person.general_agency_staff_roles.present?
      person_roles
    end

    def employee_eligibility_status(enrollment)
      if enrollment.is_shop? && enrollment.benefit_group_assignment.present?
        if enrollment.benefit_group_assignment.census_employee.can_be_reinstated?
          enrollment.benefit_group_assignment.census_employee.aasm_state.camelcase
        end
      end
    end

    def get_person_roles(person, person_roles = [])
      person_roles << "Employee Role" if person.active_employee_roles.present?
      person_roles << "Consumer Role" if person.is_consumer_role_active?
      person_roles << "Resident Role" if person.is_resident_role_active?
      person_roles << "Hbx Staff Role" if person.hbx_staff_role.present?
      person_roles << "Assister Role" if person.assister_role.present?
      person_roles << "CSR Role" if person.csr_role.present?
      person_roles << "POC" if person.employer_staff_roles.present?
      person_roles << "Broker Agency Staff Role" if person.broker_agency_staff_roles.present?
      person_roles << "General Agency Staff Role" if person.general_agency_staff_roles.present?
      person_roles
    end

    # Searches for the environment variable associated with a registry feature
    #
    # This method searches through all YAML configuration files in the
    # system/config/templates/features directory to find the ENV variable
    # that controls the given feature's enabled/disabled state.
    #
    # @param feature_key [Symbol, String] The key of the feature to search for
    # @return [String] The name of the ENV variable if found, otherwise "No ENV variable"
    # @example
    #   find_env_variable_for_feature(:qhp_application)
    #   #=> "QHP_APPLICATION_IS_ENABLED"
    #
    #   find_env_variable_for_feature(:non_existent_feature)
    #   #=> "No ENV variable"
    def find_env_variable_for_feature(feature_key)
      features_path = Rails.root.join('system', 'config', 'templates', 'features')

      Dir.glob("#{features_path}/**/*.yml").each do |file_path|
        env_variable = extract_env_variable_from_file(file_path, feature_key)
        return env_variable if env_variable
      end

      "No ENV variable"
    end

    private

    # Extracts environment variable from a single YAML file for the given feature
    #
    # @param file_path [String] Path to the YAML file
    # @param feature_key [Symbol, String] The feature key to search for
    # @return [String, nil] The ENV variable name if found, nil otherwise
    def extract_env_variable_from_file(file_path, feature_key)
      file_content = File.read(file_path)
      return nil unless file_content.include?(feature_key.to_s)

      yaml_content = parse_yaml_content(file_content)
      return nil unless yaml_content&.dig('registry')

      find_env_variable_in_registry(yaml_content['registry'], feature_key, file_content)
    rescue StandardError => e
      # Log error and skip files that can't be parsed
      Rails.logger.debug("Failed to parse feature file #{file_path}: #{e.message}")
      nil
    end

    # Parses YAML content with ERB processing
    #
    # @param file_content [String] Raw file content
    # @return [Hash, nil] Parsed YAML content or nil if parsing fails
    def parse_yaml_content(file_content)
      YAML.safe_load(ERB.new(file_content).result, permitted_classes: [Symbol])
    rescue StandardError => e
      # Log YAML parsing errors and return nil
      Rails.logger.debug("Failed to parse YAML content: #{e.message}")
      nil
    end

    # Searches for ENV variable in registry sections
    #
    # @param registry_sections [Array] Array of registry sections
    # @param feature_key [Symbol, String] The feature key to search for
    # @param file_content [String] Original file content for line parsing
    # @return [String, nil] The ENV variable name if found, nil otherwise
    def find_env_variable_in_registry(registry_sections, feature_key, file_content)
      registry_sections.each do |registry_section|
        next unless registry_section['features']

        registry_section['features'].each do |feature|
          next unless feature['key']&.to_sym == feature_key

          return extract_env_variable_from_lines(file_content, feature_key)
        end
      end
      nil
    end

    # Extracts ENV variable from file lines for a specific feature
    #
    # @param file_content [String] The file content to search
    # @param feature_key [Symbol, String] The feature key to search for
    # @return [String, nil] The ENV variable name if found, nil otherwise
    def extract_env_variable_from_lines(file_content, feature_key)
      file_lines = file_content.split("\n")
      feature_line_index = file_lines.find_index { |line| line.include?("key: :#{feature_key}") }
      return nil unless feature_line_index

      find_env_variable_after_feature_key(file_lines, feature_line_index)
    end

    # Finds ENV variable in lines after the feature key declaration
    #
    # @param file_lines [Array<String>] Array of file lines
    # @param feature_line_index [Integer] Index of the feature key line
    # @return [String, nil] The ENV variable name if found, nil otherwise
    def find_env_variable_after_feature_key(file_lines, feature_line_index)
      (feature_line_index..file_lines.length - 1).each do |i|
        line = file_lines[i]

        if line.include?('is_enabled:') && line.include?("ENV[")
          match = line.match(/ENV\['([^']+)'\]/)
          return match[1] if match
        end

        # Break if we hit the next feature
        break if i > feature_line_index && line.include?('- key:')
      end
      nil
    end
  end
end
