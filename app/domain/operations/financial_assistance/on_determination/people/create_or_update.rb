# frozen_string_literal: true

module Operations
  module FinancialAssistance
    module OnDetermination
      module People
        # This class handles the create/update of a person on the Financial Assistance (FA) application determination.
        class CreateOrUpdate
          include Dry::Monads[:do, :result]

          # Creates or updates a person based on applicant information
          #
          # @param applicant [FinancialAssistance::Applicant] The applicant containing personal information
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
                dob: applicant.dob,
                first_name: applicant.first_name,
                last_name: applicant.last_name,
                ssn: applicant.ssn
              }
            )

            return if records.blank?
            return if [:ssn_present, :dob_present].exclude?(match_criteria)
            return if match_criteria == :dob_present && applicant.ssn.present? && records.first.ssn != applicant.ssn

            records.first
          end

          # Extracts non-blank ethnicity values from applicant
          # @param applicant [Object] The applicant containing ethnicity information
          # @return [Array] Array of non-blank ethnicity values
          def fetch_ethnicity(applicant)
            # Check if the applicant's ethnicity value is a blank array or array with nil values or array with empty strings
            applicant_ethnicity = applicant.ethnicity
            return [] unless applicant_ethnicity.is_a?(Array)

            applicant_ethnicity.inject([]) do |result, ethnicity|
              result << ethnicity unless ethnicity.blank?
              result
            end
          end

          # Updates person attributes from applicant information
          # @param person [Person] The person to update
          # @param applicant [Object] The applicant containing updated information
          # @return [Dry::Monads::Result] Success with updated person
          def update_person(person, applicant)
            person.assign_attributes(
              name_pfx: applicant.name_pfx,
              first_name: applicant.first_name,
              middle_name: applicant.middle_name,
              last_name: applicant.last_name,
              name_sfx: applicant.name_sfx,
              encrypted_ssn: applicant.encrypted_ssn,
              no_ssn: applicant.no_ssn,
              gender: applicant.gender,
              dob: applicant.dob,
              is_incarcerated: applicant.is_incarcerated,
              ethnicity: fetch_ethnicity(applicant),
              race: applicant.race,
              tribal_id: applicant.tribal_id,
              tribal_state: applicant.tribal_state,
              tribal_name: applicant.tribal_name,
              tribe_codes: applicant.tribe_codes,
              is_tobacco_user: applicant.is_tobacco_user,
              language_code: applicant.language_code,
              age_off_excluded: applicant.age_off_excluded,
              is_physically_disabled: applicant.is_physically_disabled,
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
            return if applicant.vlp_subject.blank?

            # Build a new VLP document
            vlp_doc = consumer_role.vlp_documents.build
            vlp_doc.subject = applicant.vlp_subject
            vlp_doc.alien_number = applicant.alien_number
            vlp_doc.i94_number = applicant.i94_number
            vlp_doc.visa_number = applicant.visa_number
            vlp_doc.passport_number = applicant.passport_number
            vlp_doc.sevis_id = applicant.sevis_id
            vlp_doc.naturalization_number = applicant.naturalization_number
            vlp_doc.receipt_number = applicant.receipt_number
            vlp_doc.citizenship_number = applicant.citizenship_number
            vlp_doc.card_number = applicant.card_number
            vlp_doc.country_of_citizenship = applicant.country_of_citizenship
            vlp_doc.expiration_date = applicant.expiration_date
            vlp_doc.issuing_country = applicant.issuing_country
            vlp_doc.description = applicant.vlp_description

            # Sets the active_vlp_document_id to the consumer_role
            consumer_role.active_vlp_document_id = vlp_doc.id
          end

          # Builds or updates lawful presence determination for a consumer role
          # @param consumer_role [ConsumerRole] The consumer role to update
          # @param applicant [Object] The applicant containing citizenship status
          # @return [void]
          def build_or_update_lawful_presence_determination(consumer_role, applicant)
            lpd = consumer_role.lawful_presence_determination || consumer_role.build_lawful_presence_determination
            lpd.citizen_status = applicant.citizen_status
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
end
