# frozen_string_literal: true

module Operations
  module IndividualMarket
    module People
      # This class handles the create/update of a person on the Individual Market (QHP) application determination.
      class CreateOrUpdate
        include Dry::Monads[:do, :result]

        # Creates or updates a person based on applicant information
        #
        # @param applicant [IndividualMarket::Applicant] The applicant containing personal information
        # @return [Dry::Monads::Result] Success with person or Failure with error message
        def call(applicant:)
          person = yield find_or_initialize_person(applicant)
          person = yield update_person(person, applicant)
          person = yield build_or_update_consumer_role(person, applicant)
          person = yield build_addresses(person, applicant)
          person = yield build_phones(person, applicant)
          person = yield build_emails(person, applicant)
          person = yield persist(person)

          Success(person)
        end

        private

        # Finds an existing person or initializes a new one
        # @param applicant [Object] The applicant containing personal information
        # @param family [Object] The family associated with the application
        # @return [Dry::Monads::Result] Success with found or new person
        def find_or_initialize_person(applicant)
          existing_record = find_existing_person(applicant)
          if existing_record.present?
            Success(existing_record)
          else
            Success(Person.new)
          end
        end

        # Locates an existing person record based on applicant and family
        #
        # @param applicant [Object] The applicant containing personal information
        # @return [Person, nil] The found person or nil if not found
        def find_existing_person(applicant)
          if applicant.family_member_id
            applicant.family_member.person
          else
            find_person_using_matching_criteria(applicant)
          end
        end

        # Finds a person using name, DOB, and SSN matching criteria
        # @param applicant [Object] The applicant containing matching information
        # @return [Person, nil] The matched person or nil if no match found
        def find_person_using_matching_criteria(applicant)
          match_criteria, records = ::Operations::People::Match.new.call(
            {
              dob: applicant.demographics.dob,
              first_name: applicant.person_name.given_name,
              last_name: applicant.person_name.family_name,
              ssn: applicant.demographics.ssn
            }
          )

          return if records.blank?
          return if [:ssn_present, :dob_present].exclude?(match_criteria)
          return if match_criteria == :dob_present && applicant.demographics.ssn.present? && records.first.ssn != applicant.demographics.ssn

          records.first
        end

        # Extracts non-blank ethnicity values from applicant
        # Combine applicant ethnicity and race as person and FAAs combine them into one field even though different sections of the UI
        # @param applicant [Object] The applicant containing ethnicity information
        # @return [Array] Array of non-blank ethnicity values
        def fetch_ethnicity(applicant)
          ethnicity = applicant.demographics.ethnicity || []
          race = applicant.demographics.race || []
          ethnicities = ethnicity + race
          return [] unless ethnicities.is_a?(Array)

          ethnicities.compact_blank
        end

        # race is a string on the person but an array on the applicant
        # @param applicant [Object] The applicant containing race information
        # @return [String] The race value
        def assign_race(applicant)
          return nil unless applicant.demographics.race.present?
          race = applicant.demographics.race
          race.join(', ')
        end

        # Updates person attributes from applicant information
        # @param person [Person] The person to update
        # @param applicant [Object] The applicant containing updated information
        # @return [Dry::Monads::Result] Success with updated person
        def update_person(person, applicant)
          person.assign_attributes(
            name_pfx: applicant.person_name.name_pfx,
            first_name: applicant.person_name.given_name,
            middle_name: applicant.person_name.middle_name,
            last_name: applicant.person_name.family_name,
            name_sfx: applicant.person_name.name_sfx,
            encrypted_ssn: applicant.demographics.encrypted_ssn,
            no_ssn: applicant.demographics.no_ssn ? "1" : "0",
            gender: applicant.demographics.gender,
            dob: applicant.demographics.dob,
            is_incarcerated: applicant.demographics.is_incarcerated,
            ethnicity: fetch_ethnicity(applicant),
            race: assign_race(applicant),
            indian_tribe_member: applicant.demographics.indian_tribe_member,
            tribal_id: applicant.demographics.tribal_id,
            tribal_state: applicant.demographics.tribal_state,
            tribal_name: applicant.demographics.tribal_name,
            tribe_codes: applicant.demographics.tribe_codes,
            language_code: applicant.demographics.language_code,
            age_off_excluded: applicant.age_off_excluded,
            is_physically_disabled: applicant.demographics.is_physically_disabled,
            is_homeless: applicant.is_homeless,
            is_temporarily_out_of_state: applicant.is_temporarily_out_of_state
          )

          Success(person)
        end

        # Builds or updates the consumer role for a person
        # @param person [Person] The person to update
        # @param applicant [Object] The applicant containing consumer role information
        # @return [Dry::Monads::Result] Success with updated person
        def build_or_update_consumer_role(person, applicant)
          consumer_role = person.consumer_role || person.build_consumer_role

          consumer_role.is_applicant = applicant.is_primary_applicant
          consumer_role.contact_method = applicant.contact_method
          consumer_role.is_applying_coverage = applicant.is_applying_coverage
          consumer_role.language_preference = applicant.language_preference

          build_or_update_vlp_document(consumer_role, applicant)
          build_or_update_lawful_presence_determination(consumer_role, applicant)

          Success(consumer_role.person)
        end

        # Builds or updates VLP document information for a consumer role
        # @param consumer_role [ConsumerRole] The consumer role to update
        # @param applicant [Object] The applicant containing VLP document information
        # @return [void]
        def build_or_update_vlp_document(consumer_role, applicant)
          # Clear all existing VLP documents
          consumer_role.vlp_documents.clear
          return if applicant.immigration_information.blank?
          # Build a new VLP document
          vlp_doc = consumer_role.vlp_documents.build
          assign_vlp_document_attributes(vlp_doc, applicant)
          # Sets the active_vlp_document_id to the consumer_role
          consumer_role.active_vlp_document_id = vlp_doc.id
        end

        def assign_vlp_document_attributes(vlp_doc, applicant)
          vlp_doc.subject = applicant.immigration_information.subject
          vlp_doc.alien_number = applicant.immigration_information.alien_number
          vlp_doc.i94_number = applicant.immigration_information.i94_number
          vlp_doc.visa_number = applicant.immigration_information.visa_number
          vlp_doc.passport_number = applicant.immigration_information.passport_number
          vlp_doc.sevis_id = applicant.immigration_information.sevis_id
          vlp_doc.naturalization_number = applicant.immigration_information.naturalization_number
          vlp_doc.receipt_number = applicant.immigration_information.receipt_number
          vlp_doc.citizenship_number = applicant.immigration_information.citizenship_number
          vlp_doc.card_number = applicant.immigration_information.card_number
          vlp_doc.country_of_citizenship = applicant.immigration_information.country_of_citizenship
          vlp_doc.expiration_date = applicant.immigration_information.expiration_date
          vlp_doc.issuing_country = applicant.immigration_information.issuing_country
          vlp_doc.description = applicant.immigration_information.description
        end

        # Builds or updates lawful presence determination for a consumer role
        # @param consumer_role [ConsumerRole] The consumer role to update
        # @param applicant [Object] The applicant containing citizenship status
        # @return [void]
        def build_or_update_lawful_presence_determination(consumer_role, applicant)
          lpd = consumer_role.lawful_presence_determination || consumer_role.build_lawful_presence_determination
          lpd.citizen_status = applicant.demographics.citizen_status
        end

        # Builds address records for a person based on applicant information
        # @param person [Person] The person to update
        # @param applicant [Object] The applicant containing address information
        # @return [Person] The person with built addresses
        def build_addresses(person, applicant)
          # Clear existing addresses
          person.addresses.clear

          applicant.addresses.each do |address|
            person.addresses.build(
              kind: address.kind,
              address_1: address.address_1,
              address_2: address.address_2,
              city: address.city,
              state: address.state,
              zip: address.zip,
              county: address.county,
              country_name: address.country_name
            )
          end

          Success(person)
        end

        # Builds phone records for a person based on applicant information
        # @param person [Person] The person to update
        # @param applicant [Object] The applicant containing phone information
        # @return [Person] The person with built phones
        def build_phones(person, applicant)
          # Clear existing phones
          person.phones.clear

          applicant.phones.each do |phone|
            person.phones.build(
              kind: phone.kind,
              area_code: phone.area_code,
              number: phone.number,
              country_code: phone.country_code,
              extension: phone.extension,
              primary: phone.primary,
              full_phone_number: phone.full_phone_number
            )
          end

          Success(person)
        end

        # Builds email records for a person based on applicant information
        # @param person [Person] The person to update
        # @param applicant [Object] The applicant containing email information
        # @return [Person] The person with built emails
        def build_emails(person, applicant)
          # Clear existing emails
          person.emails.clear

          applicant.emails.each do |email|
            person.emails.build(address: email.address, kind: email.kind)
          end

          Success(person)
        end

        # Persists the person to the database
        # @param person [Person] The person to persist
        # @return [Dry::Monads::Result] Success with saved person or Failure with error message
        def persist(person)
          if person.valid?
            person.save!
            Success(person)
          else
            Rails.logger.error("QHP Application - Person is not valid: #{person.errors.full_messages.join(', ')}")
            Failure("Person is not valid: #{person.errors.full_messages.join(', ')}")
          end
        rescue StandardError => e
          Rails.logger.error("QHP Application - Error while saving person: #{e.message}, backtrace: #{e.backtrace.join('\n')}")
          Failure("Error while saving person with error message: #{e.message}")
        end
      end
    end
  end
end
