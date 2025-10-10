# frozen_string_literal: true

module Forms
  module IndividualMarket
    # Form object for handling Individual Market Applicant data input and validation
    # This form coordinates the creation and updating of applicant information including
    # personal details, demographics, and addresses.
    class Applicant
      include ActiveModel::Model
      include ActiveModel::Validations
      include Config::AcaModelConcern

      include ActionView::Helpers::TranslationHelper
      include L10nHelper

      attr_accessor :id,
                    :reference_id,
                    :application_id,
                    :family_member_id,
                    :is_primary_applicant,
                    :is_homeless,
                    :is_temporarily_out_of_state,
                    :age_off_excluded,
                    :address_same_as_primary,
                    :relationship,
                    :is_dependent,
                    :applicant_id

      attr_writer :person_name_form, :demographics_form, :immigration_form, :address_forms

      validate :verify_unique_dependent
      validate :validate_nested_forms
      validate :relationship_validation
      validate :check_same_ssn

      delegate :is_applying_coverage, :is_applying_coverage=, :existing_ssn, :existing_ssn=, :existing_no_ssn, :existing_no_ssn=,
               to: :demographics

      # Initializes a new Applicant form object
      # @param args [Array] Arguments passed to form initialization
      # @option args [Hash] First argument containing form attributes
      # @option args[0] [Hash] :person_name_attributes Person name form attributes
      # @option args[0] [Hash] :demographics_attributes Demographics form attributes
      # @option args[0] [Hash] :immigration_information_attributes Immigration form attributes
      # @option args[0] [Hash] :addresses_attributes Address form attributes
      # @option args[0] [Boolean] :is_primary_applicant Whether this is the primary applicant
      # @option args[0] [Boolean] :is_dependent Whether this is a dependent
      # @option args[0] [String] :family_member_id Associated family member ID
      def initialize(*args)
        super
        attributes = args.first || {}
        initialize_nested_forms(attributes)
        initialize_boolean_attributes(attributes)
        initialize_basic_attributes(attributes)

        # Pass the value to demographics form
        sync_demographics_coverage
      end

      # Sets address attributes and creates new address forms
      # @param attributes [Hash] Address attributes to set
      # @return [Array<Forms::Locations::AddressForm>] Array of address form objects
      def addresses_attributes=(attributes)
        @address_forms = attributes.values.map do |address_attrs|
          Forms::Locations::AddressForm.new(address_attrs)
        end
      end

      # Sets the is_applying_coverage flag and syncs with demographics form
      # @param value [Boolean] Whether the applicant is applying for coverage
      def is_applying_coverage=(value)
        @is_applying_coverage = value
        # Keep demographics form in sync
        @demographics_form.is_applying_coverage = value if @demographics_form
      end

      # Sets the existing_ssn flag and syncs with demographics form
      # @param value [Boolean] Applicant's existing ssn
      def existing_ssn=(value)
        @existing_ssn = value
        # Keep demographics form in sync
        @demographics_form.existing_ssn = value if @demographics_form
      end

      # Sets the existing_no_ssn flag and syncs with demographics form
      # @param value [Boolean] Applicant's existing no ssn
      def existing_no_ssn=(value)
        @existing_no_ssn = value
        # Keep demographics form in sync
        @demographics_form.existing_no_ssn = value if @demographics_form
      end

      # Checks if the form represents a persisted record
      # @return [Boolean] true if the form has an ID, false otherwise
      def persisted?
        id.present?
      end

      # Retrieves the associated application
      # @return [IndividualMarket::Application, nil] The associated application or nil if not found
      def application
        @application ||= ::IndividualMarket::Application.find(application_id) if application_id.present?
      end

      # Retrieves the associated applicant
      # @return [IndividualMarket::Applicant, nil] The associated applicant or nil if not found
      def applicant
        return @applicant if defined? @applicant
        @applicant = application.applicants.find(applicant_id) if applicant_id.present?
      end

      # Checks if a mailing address should be destroyed
      # @param address [Hash] The address attributes to check
      # @option address [String] :kind The type of address
      # @option address [String] :_destroy Whether to destroy the address ('true' or 'false')
      # @option address [String, nil] :id The address ID if it exists
      # @return [Boolean] true if the address should be destroyed, false otherwise
      def destroy_mailing_address?(applicant)
        applicant.mailing_address.present? && applicant_params[:addresses].detect{|a| a[:id].present? && a[:kind] == 'mailing' && a[:_destroy] == "true"}.present?
      end

      # Saves the form data and creates or updates the applicant
      # @return [Array<(Boolean, IndividualMarket::Applicant, Hash)>] Success flag and either the applicant or error messages
      def save
        return [false, self.errors.full_messages] unless valid?

        applicant_entity = build_applicant_entity
        return handle_failure(applicant_entity) unless applicant_entity.success?

        values = applicant_entity.success.to_h
        updated_applicant = find_or_build_applicant(values)
        unless updated_applicant.individual_market_eligibility.present?
          updated_applicant.build_individual_market_eligibility
          updated_applicant.eligibilities.last.save
        end
        return [false, updated_applicant.errors.full_messages] unless updated_applicant.valid?

        result = ssn_is_taken?(values)
        return [false, result[1]] if result[0]

        build_relationship(updated_applicant)
        return [false, updated_applicant.errors.full_messages] unless updated_applicant.save
        return [false, application.errors.full_messages] unless application.save
        application.reload
        [true, updated_applicant]
      end

      # Sets demographics form attributes
      # @param attributes [Hash] Demographics attributes to set
      def demographics_attributes=(attributes)
        @demographics_form = DemographicsForm.new(attributes)
      end

      # Sets immigration information form attributes
      # @param attributes [Hash] Immigration information attributes to set
      def immigration_information_attributes=(attributes)
        @immigration_form = ImmigrationInformationForm.new(attributes)
      end

      # Gets the person name form object
      # @return [Forms::IndividualMarket::PersonNameForm] The person name form
      def person_name_attributes=(attributes)
        @person_name_form = PersonNameForm.new(attributes)
      end

      def person_name
        @person_name_form
      end

      # Gets the address forms
      # @return [Array<Forms::Locations::AddressForm>] Array of address forms
      def addresses
        @address_forms
      end

      # Gets the demographics form object
      # @return [Forms::IndividualMarket::DemographicsForm] The demographics form
      def demographics
        @demographics_form
      end

      # Gets the immigration information form object
      # @return [Forms::IndividualMarket::ImmigrationInformationForm] The immigration information form
      def immigration_information
        @immigration_form
      end

      # Gets or initializes the address forms array
      # @return [Array<Forms::Locations::AddressForm>] Array of address forms
      def address_forms
        @address_forms ||= []
      end

      # Synchronizes the demographics coverage status with the form's status
      # @return [void]
      def sync_demographics_coverage
        @demographics_form.is_applying_coverage = @is_applying_coverage if @demographics_form
        @demographics_form.existing_ssn = @existing_ssn if @demographics_form
        @demographics_form.existing_no_ssn = @existing_no_ssn if @demographics_form
      end

      private

      # Initializes all nested form objects with provided attributes
      # @param attributes [Hash] The attributes to initialize forms with
      # @option attributes [Hash] :person_name_attributes Person name attributes
      # @option attributes [Hash] :demographics_attributes Demographics attributes
      # @option attributes [Hash] :immigration_information_attributes Immigration information attributes
      # @option attributes [Hash] :addresses_attributes Address attributes
      # @return [void]
      def initialize_nested_forms(attributes)
        @person_name_form = PersonNameForm.new(attributes[:person_name_attributes] || {})
        @demographics_form = DemographicsForm.new(demographics_params(attributes))
        @immigration_information_form = ImmigrationInformationForm.new(attributes[:immigration_information_attributes] || {})
        @address_forms = build_address_forms(attributes[:addresses_attributes])
      end

      # Builds address form objects from attributes
      # @param addresses_attributes [Hash] The address attributes to build forms from
      # @return [Array<Forms::Locations::AddressForm>] Array of address forms
      def build_address_forms(addresses_attributes)
        return [] unless addresses_attributes.present?

        addresses_attributes.values.map do |addr_attrs|
          Forms::Locations::AddressForm.new(addr_attrs)
        end
      end

      # Builds demographics attributes
      def demographics_params(attributes)
        return {} unless attributes[:demographics_attributes].present?
        demographics = attributes[:demographics_attributes]
        return demographics unless existing_ssn.present? || existing_no_ssn.present?
        demographics[:existing_ssn] = existing_ssn
        demographics[:existing_no_ssn] = existing_no_ssn
        demographics
      end

      # Initializes boolean attributes with type casting
      # @param attributes [Hash] The attributes containing boolean values
      # @return [void]
      def initialize_boolean_attributes(attributes)
        boolean_type = ActiveModel::Type::Boolean.new
        @is_primary_applicant = boolean_type.cast(attributes['is_primary_applicant'] || attributes[:is_primary_applicant])
        @is_dependent = boolean_type.cast(attributes['is_dependent'] || attributes[:is_dependent])
      end

      # Initializes basic attributes from the provided hash
      # @param attributes [Hash] The attributes to initialize
      # @return [void]
      def initialize_basic_attributes(attributes)
        @family_member_id = attributes['family_member_id'] || attributes[:family_member_id]
        @address_same_as_primary = attributes[:address_same_as_primary] || true
        @is_applying_coverage = attributes[:is_applying_coverage] || true
        @is_homeless = attributes[:is_homeless]
        @age_off_excluded = attributes[:age_off_excluded]
        @id = attributes['id'] || attributes[:id]
        @application_id = attributes['application_id'] || attributes[:application_id]
        @relationship = attributes[:relationship]
        @applicant_id = attributes['applicant_id'] || attributes[:applicant_id] || @id
      end

      # Validates all nested form objects
      # @private
      def validate_nested_forms
        validate_person_name
        validate_demographics
        validate_immigration if needs_immigration_information?
        validate_addresses
      end

      # Validates the person name form
      # @private
      def validate_person_name
        return if person_name.valid?
        person_name.errors.each do |error|
          errors.add(:base, "#{error.attribute} #{error.message}")
        end
      end

      # Validates the demographics form
      # @private
      def validate_demographics
        return if demographics.valid?
        demographics.errors.each do |error|
          errors.add(:base, "#{error.attribute} #{error.message}")
        end
      end

      # Validates the immigration form
      # @private
      def validate_immigration
        return if immigration_information.valid?
        immigration_information.errors.each do |error|
          errors.add(:base, "#{error.attribute} #{error.message}")
        end
      end

      # Validates the addresses
      # @private
      def validate_addresses
        return if address_same_as_primary == "true"

        address_forms.each do |address_form|
          next if address_form.valid?
          next unless address_form.skip_validation?
          address_form.errors.each do |error|
            errors.add(:base, "#{error.attribute} #{error.message}")
          end
        end
      end

      # Collects all form data into parameters for entity creation
      # @private
      # @return [Hash] Combined parameters from all form objects
      def applicant_params
        params = {
          id: id,
          applicant_id: applicant_id,
          family_member_id: family_member_id,
          is_primary_applicant: is_primary_applicant,
          is_dependent: is_dependent,
          is_applying_coverage: @is_applying_coverage,
          is_homeless: is_homeless,
          age_off_excluded: age_off_excluded,
          address_same_as_primary: @address_same_as_primary,
          person_name: person_name&.to_h,
          demographics: demographics&.to_h,
          immigration_information: immigration_params,
          eligibilities: eligibilities,
          addresses: addresses_params
        }

        if is_primary_applicant.to_s == "false" && address_same_as_primary == "true"
          primary = application&.primary_applicant
          params.merge!(is_homeless: primary&.is_homeless?)
        end
        params
      end

      # Gets immigration parameters if needed
      # @private
      # @return [Hash] Immigration parameters or empty hash
      def immigration_params
        return {} unless needs_immigration_information?
        immigration_information.to_h
      end

      # Processes address parameters
      # @private
      # @return [Array<Hash>] Array of address parameters
      def addresses_params
        return primary_address_params if is_primary_applicant.to_s == "false" && address_same_as_primary == "true"
        return [] if addresses.nil?

        addresses.select { |address| address.skip_validation? == false }.map(&:to_h).compact
      end

      def primary_address_params
        applicant&.home_address&.destroy
        primary = application.primary_applicant
        home_address = primary.addresses.in(kind: 'home').first
        return [] unless home_address

        [home_address.attributes.to_h.slice('address_1', 'address_2', 'address_3', 'county',
                                            'country_name', 'kind', 'city', 'state', 'zip')]
      end

      # Determines if immigration information is needed
      # @private
      # @return [Boolean] Whether immigration information is required
      def needs_immigration_information?
        (demographics&.us_citizen == false &&
          demographics&.eligible_immigration_status == true) ||
          demographics&.naturalized_citizen == true
      end

      # Validates relationship selection
      # @private
      def relationship_validation
        return unless relationship.present?
        return if is_primary_applicant
        errors.add(:relationship, "is invalid") unless valid_relationship?
      end

      # Checks if the relationship is valid
      # @private
      # @return [Boolean] Whether the relationship is valid
      def valid_relationship?
        # Add relationship validation logic
        true
      end

      # Verifies that the dependent is not a duplicate
      # @private
      def verify_unique_dependent
        return if skip_duplicate_check?

        add_duplicate_error if duplicate_exists?
      end

      # Determines if duplicate checking should be skipped
      # @return [Boolean] Whether to skip the duplicate check
      def skip_duplicate_check?
        persisted? || application.blank? || application.applicants.blank?
      end

      # Checks if a duplicate applicant exists
      # @return [Boolean] Whether a duplicate exists
      def duplicate_exists?
        application.applicants.any? do |existing_applicant|
          matches_existing_applicant?(existing_applicant)
        end
      end

      # Checks if an existing applicant matches the current form data
      # @param existing_applicant [IndividualMarket::Applicant] The applicant to check against
      # @return [Boolean] Whether the applicants match
      def matches_existing_applicant?(existing_applicant)
        existing_applicant&.person_name&.given_name == person_name&.given_name &&
          existing_applicant&.person_name&.family_name == person_name&.family_name &&
          existing_applicant&.demographics&.dob&.to_date == demographics&.dob&.to_date
      end

      # Adds a duplicate error message to the errors collection
      # @return [void]
      def add_duplicate_error
        duplicate_message = l10n('qhp_application.duplicate_applicant_error_message')
        errors.add(:base, duplicate_message)
      end

      # Initializes default eligibilities
      # @private
      # @return [Array<Hash>] Array of default eligibility attributes
      def eligibilities
        if persisted? && applicant.eligibilities&.any?
          applicant.eligibilities.map(&:attributes)
        else
          [{
            key: :individual_market_eligibility,
            title: "Individual Market Eligibility",
            _type: "Eligibilities::V3::IndividualMarketEligibility"
          }]
        end
      end

      # Builds or updates the relationship between the applicant and primary applicant
      # @param applicant [IndividualMarket::Applicant] The applicant to build/update relationship for
      # @param relationship [String] The relationship kind to set
      # @return [void]
      def build_relationship(applicant)
        return if applicant.is_primary_applicant
        primary_id = application.primary_applicant.id
        existing_relationship = application.relationships.where(
          source_id: applicant.id,
          relative_id: primary_id
        )&.first

        if existing_relationship
          # Only update if the relationship kind has changed
          existing_relationship.update(kind: @relationship) if existing_relationship.kind != @relationship
        else
          application.relationships.new({
                                          source_id: applicant.id,
                                          relative_id: primary_id,
                                          kind: @relationship
                                        })
        end
      end

      # Builds an applicant entity from the form parameters
      # @return [Result] Operation result containing the built entity or errors
      def build_applicant_entity
        ::Operations::IndividualMarket::Applicant::Build.new.call(
          params: applicant_params
        )
      end

      # Handles failure cases from entity building
      # @param applicant_entity [Result] The failed operation result
      # @return [Array<(Boolean, Hash)>] Array containing false and the error messages
      def handle_failure(applicant_entity)
        applicant_entity.failure.each do |key, msg|
          errors.add(:base, "#{key} #{msg[0]}")
        end
        [false, applicant_entity.failure]
      end

      # Finds an existing applicant or builds a new one
      # @param values [Hash] The values to update or create with
      # @return [IndividualMarket::Applicant] The found or newly built applicant
      def find_or_build_applicant(values)
        applicant = application.applicants.find(applicant_id) if applicant_id.present?
        if applicant.present? && applicant.persisted?
          update_existing_applicant(applicant, values)
        else
          create_new_applicant(values)
        end
      end

      # Updates an existing applicant with new values
      # @param applicant [IndividualMarket::Applicant] The applicant to update
      # @param values [Hash] The values to update with
      # @return [IndividualMarket::Applicant] The updated applicant
      def update_existing_applicant(applicant, values)
        applicant.update(values.except(:eligibilities))
        applicant.save
        handle_address_changes(applicant)
        applicant
      end

      # Creates a new applicant with the provided values
      # @param values [Hash] The values to create the applicant with
      # @return [IndividualMarket::Applicant] The newly created applicant
      def create_new_applicant(values)
        applicant = application.applicants.build
        applicant.assign_attributes(values.except(:eligibilities))
        applicant.save
        applicant
      end

      # Handles address changes for an applicant
      # @param applicant [IndividualMarket::Applicant] The applicant whose addresses need handling
      # @return [Boolean] The result of saving the applicant
      def handle_address_changes(applicant)
        # Handle mailing address
        applicant.mailing_address.destroy! if destroy_mailing_address?(applicant)
      end

      def check_same_ssn
        values = {
          demographics: demographics.to_h,
          person_name: person_name.to_h
        }

        result = ssn_is_taken?(values)
        return if result[0]

        ssn = self.demographics.ssn
        return if ssn.blank?

        matching_applicants = application.applicants.select {|s| s.demographics.ssn == ssn && s.id.to_s != self.id.to_s }

        if applicant_id.present?
          # Filter out the current applicant
          matching_applicants = matching_applicants.reject {|a| a.id.to_s == applicant_id.to_s}
        end

        return unless matching_applicants.any?
        errors.add(:base, 'The entered SSN is already taken by another applicant in this application.')
      end

      # Checks if the SSN is already taken by a non-matching Person.
      # This method is used to prevent duplicate SSNs from being saved in the system.
      #
      # @param values [Hash] the values to check, including the SSN
      # @return [Boolean] true if the SSN is taken, false otherwise
      def ssn_is_taken?(values)
        return [false, nil] if values[:demographics][:ssn].blank?

        matching_params = {
          dob: values[:demographics][:dob].to_date,
          first_name: values[:person_name][:given_name],
          last_name: values[:person_name][:family_name],
          ssn: values[:demographics][:ssn]
        }

        # if the matching criteria (dob, first name, last name) has changed for an existing person,
        # we need to make sure the check isn't failing on the existing person
        if applicant&.family_member&.present?
          person = applicant.family_member.person
          matching_params[:skipped_person] = person&.hbx_id if person.present? && matching_criteria_changed?(matching_params, person)
        end

        result = ::Operations::People::SsnTaken.new.call(matching_params)

        if result.success?
          if result.success
            errors.add(:base, 'ssn is already taken')
            [result.success, 'ssn is already taken']
          else
            [result.success, nil]
          end
        else
          errors.add(:base, "Operation failure while checking SSN: #{result.failure}")
          Rails.logger.error "QHP Application - SSN Taken Operation Failure: #{result.failure}"
          [true, "Operation failure while checking SSN: #{result.failure}"]
        end
      rescue StandardError => e
        errors.add(:base, "Error raised checking SSN: #{e.message}")
        Rails.logger.error "QHP Application - SSN Taken Error: #{e.message}, backtrace: #{e.backtrace.join("\n")}"
        [true, "Error raised checking SSN: #{e.message}"]
      end

      def matching_criteria_changed?(matching_params, person)
        # return true if the ssn has changed as still want to check in that case
        return false unless matching_params[:ssn] == person.ssn
        matching_params[:dob] != person.dob || matching_params[:first_name] != person.first_name || matching_params[:last_name] != person.last_name
      end

    end
  end
end
