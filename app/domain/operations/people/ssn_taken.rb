# frozen_string_literal: true

module Operations
  module People
    # Determines if a provided SSN is already taken by another person
    # with different identifying information in the system.
    #
    # This operation helps prevent SSN conflicts while allowing legitimate
    # matches when all other identifying information is the same.
    class SsnTaken
      include Dry::Monads[:do, :result]

      # Executes the SSN taken check operation
      #
      # @param params [Hash] The parameters to check for SSN conflict
      # @option params [String] :ssn Social Security Number to check
      # @option params [Date] :dob Date of birth of the person
      # @option params [String] :first_name (optional) First name of the person
      # @option params [String] :last_name (optional) Last name of the person
      # @option params [String] :skipped_person (optional) Hbx ID of the person to skip the check, used when updating the matching criteria of an existing person
      # @return [Dry::Monads::Result] Success(true) if SSN is taken, Success(false) if not taken,
      #                              or Failure with error message on invalid input
      def call(params)
        expected_params = yield fetch_expected_param_list
        valid_params    = yield validate(expected_params, params)
        taken           = yield is_taken?(expected_params, valid_params)

        Success(taken)
      end

      private

      # Fetches the expected parameter list from the EnrollRegistry of the feature :person_match_policy with the setting :ssn_present.
      #
      # @return [Dry::Monads::Result] Success with the list of expected parameters or Failure with an error message if the feature is disabled.
      def fetch_expected_param_list
        if EnrollRegistry.feature_enabled?(:person_match_policy)
          Success(EnrollRegistry[:person_match_policy].settings(:ssn_present).item.map(&:to_sym).sort)
        else
          Failure('person_match_policy is disabled')
        end
      end

      # Validates the provided parameters against the expected parameters.
      #
      # @param expected_params [Array<Symbol>] The list of expected parameters.
      # @param params [Hash] The parameters to validate.
      # @return [Dry::Monads::Result] Success with the validated parameters or Failure with an error message if validation fails.
      def validate(expected_params, params)
        failures = expected_params.map do |param|
          validate_param(param, params)
        end.compact

        failures << validate_skipped_person(params[:skipped_person]) if params.key?(:skipped_person)

        return failures.first if failures.any?
        Success(params)
      end

      # Validates a single parameter based on its type and requirements.
      #
      # @param param [Symbol] The parameter to validate (e.g., :encrypted_ssn, :dob, :first_name, :last_name).
      # @param params [Hash] The parameters to validate against.
      # @return [Dry::Monads::Result] Returns nil if valid, or Failure with an error message if invalid.
      def validate_param(param, params)
        case param
        when :encrypted_ssn
          validate_ssn(params)
        when :dob
          validate_date_param(:dob, params)
        when :first_name, :last_name
          validate_string_param(param, params)
        end
      end

      # Validates the SSN parameter.
      #
      # @param params [Hash] The parameters to validate.
      # @return [Dry::Monads::Result] Returns nil if valid, or Failure with an error message if invalid.
      def validate_ssn(params)
        return Failure("Missing required parameter: ssn") unless params.key?(:ssn)
        return Failure("SSN is not valid.") unless params[:ssn].is_a?(String) && params[:ssn].match?(/^\d{9}$/)
        nil
      end

      # Validates a date parameter.
      #
      # @param param [Symbol] The parameter to validate (e.g., :dob).
      # @param params [Hash] The parameters to validate against.
      def validate_date_param(param, params)
        return Failure("Missing required parameter: #{param}") unless params.key?(param)
        return Failure("#{param.to_s.upcase} is not valid.") unless params[param].is_a?(Date)
        nil
      end

      # Validates a string parameter.
      #
      # @param param [Symbol] The parameter to validate (e.g., :first_name, :last_name).
      # @param params [Hash] The parameters to validate against.
      def validate_string_param(param, params)
        return Failure("Missing required parameter: #{param}") unless params.key?(param)
        return Failure("#{param} is not valid.") unless params[param].is_a?(String)
        nil
      end

      # Validates a string parameter.
      #
      # @param hbx_id [String] The Hbx ID of the person to skip the check.
      def validate_skipped_person(hbx_id)
        return Failure("skipped_person is not valid.") unless hbx_id.is_a?(String)
        nil
      end

      # Determines if an SSN is taken by checking for the existence of people with the same SSN
      # but different identifying information.
      #
      # The logic follows three steps:
      # 1. If no person exists with the given SSN, the SSN is not taken.
      # 2. If multiple people exist with the same SSN, the SSN is considered taken.
      # 3. If one person exists with the SSN, compare other identifying information:
      #    - If any expected parameter (DOB, first name, last name) doesn't match, the SSN is taken.
      #    - If all parameters match, this is not a taken SSN but a person match.
      #
      # @param expected_params [Array<Symbol>] The list of parameters to compare.
      # @param valid_params [Hash] The validated parameters containing the SSN and other identifying information.
      # @return [Dry::Monads::Result] Success(true) if SSN is taken, Success(false) if not taken.
      def is_taken?(expected_params, valid_params)
        encrypted_ssn = Person.encrypt_ssn(valid_params[:ssn])
        people = Person.where(encrypted_ssn: encrypted_ssn)

        if people.empty?
          # No person exists with the given SSN, so it's not taken
          return Success(false)
        end

        if people.count > 1
          # More than one person exists with the same SSN, so it's a taken case
          return Success(true)
        end

        person = people.first

        # if the person is the same person as the skipped person, we can skip the check
        return Success(false) if valid_params[:skipped_person] && valid_params[:skipped_person] == person.hbx_id

        expected_params.each do |param|
          case param
          when :dob
            # Dob does not match the person's date of birth, so it's a taken SSN case
            return Success(true) if person.dob != valid_params[:dob]
          when :first_name
            # First name does not match the person's first name, so it's a taken SSN case
            return Success(true) if person.first_name != valid_params[:first_name]
          when :last_name
            # Last name does not match the person's last name, so it's a taken SSN case
            return Success(true) if person.last_name != valid_params[:last_name]
          end
        end

        # All parameters match, so it's not a taken SSN case
        Success(false)
      end
    end
  end
end
