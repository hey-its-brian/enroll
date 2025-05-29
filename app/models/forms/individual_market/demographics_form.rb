# frozen_string_literal: true

module Forms
  module IndividualMarket
    # Form object for managing demographics information for an individual
    # Handles personal information, citizenship status, tribal membership, and other demographic details
    class DemographicsForm
      include ActiveModel::Model
      include ActiveModel::Validations
      include Config::AcaModelConcern
      include ::Forms::DateOfBirthField
      include ::Forms::SsnField

      # @!attribute [rw] gender
      #   @return [String] The person's gender
      # @!attribute [rw] ethnicity
      #   @return [Array<String>] List of ethnicities
      # @!attribute [rw] race
      #   @return [String] The person's race
      # @!attribute [rw] is_incarcerated
      #   @return [Boolean] Whether the person is incarcerated
      # @!attribute [rw] is_physically_disabled
      #   @return [Boolean] Whether the person is physically disabled
      # @!attribute [rw] tribal_id
      #   @return [String] The tribal identification number
      # @!attribute [rw] tribal_name
      #   @return [String] The name of the tribe
      # @!attribute [rw] tribal_state
      #   @return [String] The state where the tribe is located
      # @!attribute [rw] language_code
      #   @return [String] Preferred language code
      # @!attribute [rw] tribe_codes
      #   @return [Array<String>] List of tribal codes
      # @!attribute [rw] citizen_status
      #   @return [String] The person's citizenship status
      # @!attribute [rw] dob
      #   @return [Date] Date of birth
      # @!attribute [rw] ssn
      #   @return [String] Social Security Number
      # @!attribute [rw] no_ssn
      #   @return [Boolean] Whether the person has no SSN
      # @!attribute [rw] is_applying_coverage
      #   @return [Boolean] Whether the person is applying for coverage
      # @!attribute [rw] id
      #   @return [String] The unique identifier
      attr_accessor :gender,
                    :ethnicity,
                    :race,
                    :is_incarcerated,
                    :is_physically_disabled,
                    :tribal_id,
                    :tribal_name,
                    :tribal_state,
                    :language_code,
                    :tribe_codes,
                    :citizen_status,
                    :dob,
                    :ssn,
                    :encrypted_ssn,
                    :no_ssn,
                    :is_applying_coverage,
                    :id

      validates :gender, :dob, presence: true
      validates :ssn,
                length: { minimum: 9, maximum: 9, message: "must be 9 digits" },
                allow_blank: true,
                numericality: true
      validate :ssn_validation
      validate :consumer_fields_validation

      # Initializes a new DemographicsForm
      # @param attributes [Hash] The attributes to initialize the form with
      # @option attributes [String] :gender The person's gender
      # @option attributes [Array<String>] :ethnicity List of ethnicities
      # @option attributes [String] :race The person's race
      # @option attributes [Boolean] :is_applying_coverage Whether applying for coverage (defaults to true)
      def initialize(attributes = {})
        super
        self.ssn = ssn&.to_s&.gsub(/\D/, '')
      end

      # Converts the form object to a hash of attributes
      # @return [Hash] The form data as a hash with non-nil values
      def to_h
        assign_citizen_status
        {
          dob: dob,
          gender: gender,
          ssn: ssn,
          encrypted_ssn: encrypted_ssn,
          no_ssn: no_ssn,
          ethnicity: Array(ethnicity).reject(&:blank?),
          race: race,
          is_incarcerated: is_incarcerated,
          is_physically_disabled: is_physically_disabled,
          indian_tribe_member: @indian_tribe_member,
          tribal_id: tribal_id,
          tribal_name: tribal_name,
          tribal_state: tribal_state,
          language_code: language_code,
          tribe_codes: Array(tribe_codes).reject(&:blank?),
          citizen_status: citizen_status
        }.compact
      end

      # Sets the US citizen status
      # @param val [String] The citizenship value ('true' or 'false')
      # @return [void]
      def us_citizen=(val)
        return if val.to_s.blank?

        @us_citizen = (val.to_s == "true")
        @naturalized_citizen = false if val.to_s == "false"
      end

      # Sets the naturalized citizen status
      # @param val [String] The naturalized status value ('true' or 'false')
      # @return [void]
      def naturalized_citizen=(val)
        return if val.to_s.blank?

        @naturalized_citizen = (val.to_s == "true")
      end

      # Sets the Indian tribe member status
      # @param val [String] The tribe member status value ('true' or 'false')
      # @return [void]
      def indian_tribe_member=(val)
        @indian_tribe_member = if val.to_s.present?
                                 (val.to_s == "true")
                               end
      end

      # Sets the eligible immigration status
      # @param val [String] The immigration status value ('true' or 'false')
      # @return [void]
      def eligible_immigration_status=(val)
        return if val.to_s.blank?

        @eligible_immigration_status = (val.to_s == "true")
      end

      # Gets the US citizen status
      # @return [Boolean, nil] The US citizen status or nil if not set
      def us_citizen
        return @us_citizen unless @us_citizen.nil?
        return nil if @citizen_status.blank?
        @us_citizen ||= ::ConsumerRole::US_CITIZEN_STATUS_KINDS.include?(@citizen_status)
      end

      # Gets the naturalized citizen status
      # @return [Boolean, nil] The naturalized citizen status or nil if not set
      def naturalized_citizen
        return @naturalized_citizen unless @naturalized_citizen.nil?
        return nil if @us_citizen.nil? || @us_citizen
        @naturalized_citizen ||= (::ConsumerRole::NATURALIZED_CITIZEN_STATUS == @citizen_status)
      end

      # Gets the Indian tribe member status
      # @return [Boolean, nil] The tribe member status or nil if not set
      def indian_tribe_member
        return @indian_tribe_member unless @indian_tribe_member.nil?
        return nil if @indian_tribe_member.nil?
        @indian_tribe_member ||= (@indian_tribe_member == true)
      end

      # Gets the eligible immigration status
      # @return [Boolean, nil] The immigration eligibility status or nil if not set
      def eligible_immigration_status
        return @eligible_immigration_status unless @eligible_immigration_status.nil?
        return nil if @us_citizen.nil? || !@us_citizen
        @eligible_immigration_status ||= (::ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS == @citizen_status)
      end

      # Assigns the appropriate citizen status based on current citizenship values
      # @return [String, nil] The assigned citizen status or nil if no status can be determined
      def assign_citizen_status
        @citizen_status = if naturalized_citizen
                            ::ConsumerRole::NATURALIZED_CITIZEN_STATUS
                          elsif us_citizen
                            ::ConsumerRole::US_CITIZEN_STATUS
                          elsif eligible_immigration_status
                            ::ConsumerRole::ALIEN_LAWFULLY_PRESENT_STATUS
                          elsif !eligible_immigration_status.nil?
                            ::ConsumerRole::NOT_LAWFULLY_PRESENT_STATUS
                          end
      end

      private

      # Validates tribal information if person is a tribe member
      # @return [void]
      def validate_tribal_information
        return unless indian_tribe_member
        # Add tribal validation logic
      end

      # Validates SSN requirements based on coverage application status
      # @return [Boolean] true if validation passes
      def ssn_validation
        return unless is_applying_coverage
        return true if is_applying_coverage.to_s == "false"
        return true unless individual_market_is_enabled?

        self.errors.add(:base, "SSN is required") if @ssn.blank? && @no_ssn == '0'
      end

      # Validates consumer-specific fields based on role and coverage status
      # @return [Boolean] true if validation passes or is not required
      def consumer_fields_validation
        return true unless individual_market_is_enabled?
        return unless is_applying_coverage == true

        validate_citizen_status
        validate_native_american_status
        validate_incarceration_status
      end

      # Validates citizenship status requirements
      # @return [void]
      def validate_citizen_status
        error_message = if @us_citizen.nil?
                          "Citizenship status is required"
                        elsif @us_citizen == false && (@eligible_immigration_status.nil? && EnrollRegistry[:immigration_status_question_required].item)
                          "Eligible immigration status is required"
                        elsif @us_citizen == true && @naturalized_citizen.nil?
                          "Naturalized citizen is required"
                        end
        self.errors.add(:base, error_message) if error_message.present?
      end

      # Validates Native American/Alaska Native status requirements
      # @return [void]
      def validate_native_american_status
        self.errors.add(:base, "Native american / alaska native status is required") if @indian_tribe_member.nil?
        validate_tribe_details if @indian_tribe_member
      end

      # Validates incarceration status requirement
      # @return [void]
      def validate_incarceration_status
        self.errors.add(:base, "Incarceration status is required") if @is_incarcerated.nil?
      end

      # Validates tribal details when person is a tribe member
      # @return [void]
      def validate_tribe_details
        if EnrollRegistry[:indian_alaskan_tribe_details].enabled?
          errors.add(:tribal_state, "is required when native american / alaska native is selected") unless tribal_state.present?
          validate_featured_tribes if FinancialAssistanceRegistry[:featured_tribes_selection].enabled?
          errors.add(:tribal_name, "is required when native american / alaska native is selected") if !tribal_name.present? && !FinancialAssistanceRegistry[:featured_tribes_selection].enabled?
          errors.add(:tribal_name, "cannot contain numbers") unless (tribal_name =~ /\d/).nil?
        else
          errors.add(:tribal_id, "is required when native american / alaska native is selected") unless tribal_id.present?
          errors.add(:tribal_id, "Tribal id must be 9 digits") if tribal_id.present? && !tribal_id.match("[0-9]{9}")
        end
      end

      # Validates featured tribes selection based on tribal state
      # @return [void]
      def validate_featured_tribes
        if tribal_state == EnrollRegistry[:enroll_app].setting(:state_abbreviation).item
          errors.add(:tribal_name, "is required when native american / alaska native is selected") if tribe_codes.include?("OT") && !tribal_name.present?
          errors.add(:base, "At least one tribe must be selected") if tribe_codes.empty?
        else
          errors.add(:tribal_name, "is required when native american / alaska native is selected") unless tribal_name.present?
        end
      end

    end
  end
end