# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/libraries/individual_market_library'

module Operations
  module IndividualMarket
    module Transformers
      module ApplicationTo
        # Transforms an instance of IndividualMarket::Application to CV3 format
        # @example Transform an application to CV3 format
        #   application = IndividualMarket::Application.find('123')
        #   result = Operations::IndividualMarket::Transformers::ApplicationTo::Cv3Application.new.call(application)
        #   if result.success?
        #     cv3_payload = result.value!
        #   else
        #     error_message = result.failure
        #   end
        #
        # @note This transformer handles the conversion of all embedded documents
        #       and relationships from the application model to the format expected
        class Cv3Application
          include Dry::Monads[:do, :result]
          # include Acapi::Notifiers

          # Transforms an IndividualMarket::Application instance to CV3 format
          #
          # @param [IndividualMarket::Application] application The application to transform
          # @return [Dry::Monads::Result::Success<Hash>] On successful transformation
          # @return [Dry::Monads::Result::Failure<String>] On transformation failure
          def call(application)
            application = yield validate(application)
            request_payload = yield construct_payload(application)

            Success(request_payload)
          end

          private

          # Validates that the input is a valid and persisted IndividualMarket::Application
          #
          # @param [Object] application The application object to validate
          # @return [Dry::Monads::Result::Success<IndividualMarket::Application>] If valid
          # @return [Dry::Monads::Result::Failure<String>] If invalid
          def validate(application)
            return Failure("Should be an instance of IndividualMarket::Application") unless application.is_a?(::IndividualMarket::Application)
            return Failure("Application is not persisted") unless application.persisted?

            Success(application)
          end

          # Constructs the main CV3 payload from the application
          #
          # @param [IndividualMarket::Application] application The application to transform
          # @return [Dry::Monads::Result::Success<Hash>] The transformed application payload
          def construct_payload(application)
            payload = {
              family_reference: {hbx_id: application.family.hbx_assigned_id.to_s},
              assistance_year: application.assistance_year || TimeKeeper.date_of_record.year,
              hbx_id: application.hbx_id,
              effective_on: application.effective_on || TimeKeeper.date_of_record,
              submitted_at: application.submitted_at || DateTime.now,
              is_renewal: application.is_renewal,
              predecessor_id: predecessor_reference(application.predecessor_id),
              origin: application.origin,
              generation_reason: application.generation_reason,
              current_state: application.current_state,
              applicants: applicants(application),
              attestation: attestation(application),
              relationships: relationships(application),
              _type: application._type
            }

            Success(payload)
          end

          # Transforms all applicants in the application to their CV3 representation
          #
          # @param [IndividualMarket::Application] application The application containing applicants
          # @return [Array<Hash>] Collection of transformed applicant hashes
          def applicants(application)
            application.applicants.inject([]) do |result, applicant|
              applicant_hash = {
                person_name: name(applicant),
                demographics: demographics(applicant),
                eligibilities: eligibilities(applicant),
                family_member_reference: family_member_reference(applicant),
                is_primary_applicant: applicant.is_primary_applicant,
                address_same_as_primary: applicant.address_same_as_primary,
                is_applying_coverage: applicant.is_applying_coverage,
                is_homeless: applicant.is_homeless,
                addresses: addresses(applicant),
                hbx_id: applicant.hbx_id,
                contact_method: applicant.contact_method,
                age_of_applicant: applicant.age_of_applicant
              }

              applicant_hash.merge!(immigration_information: immigration_information(applicant)) if applicant.immigration_information.present?
              result << applicant_hash
              result
            end
          end

          def predecessor_reference(predecessor_id)
            return nil unless predecessor_id.present?
            predecessor = ::IndividualMarket::Application.find(predecessor_id)

            {
              application_hbx_id: predecessor.hbx_id,
              assistance_year: predecessor.assistance_year,
              current_state: predecessor.current_state,
              effective_on: predecessor.effective_on
            }
          end

          # Transforms an applicant's person_name to its CV3 representation
          #
          # @param [IndividualMarket::Applicant] applicant The applicant whose name to transform
          # @return [Hash] The transformed name hash
          def name(applicant)
            p_name = applicant.person_name
            {
              given_name: p_name.given_name,
              middle_name: p_name.middle_name,
              family_name: p_name.family_name,
              name_sfx: p_name.name_sfx,
              name_pfx: p_name.name_pfx,
              alternate_name: p_name.alternate_name
            }
          end

          # Transforms an applicant's demographics to its CV3 representation
          #
          # @param [IndividualMarket::Applicant] applicant The applicant whose demographics to transform
          # @return [Hash] The transformed demographics hash
          def demographics(applicant)
            demographics = applicant.demographics
            demographics_hash = {
              no_ssn: demographics.no_ssn,
              is_incarcerated: demographics.is_incarcerated,
              is_physically_disabled: demographics.is_physically_disabled,
              indian_tribe_member: demographics.indian_tribe_member,
              tribal_id: demographics.tribal_id,
              tribal_name: demographics.tribal_name,
              tribal_state: demographics.tribal_state,
              language_code: demographics.language_code,
              ethnicity: demographics.ethnicity,
              citizen_status: demographics.citizen_status,
              race: demographics.race
            }
            demographics_hash[:gender] = demographics.gender.capitalize
            demographics_hash[:encrypted_ssn] = encrypt(demographics.ssn) if demographics.encrypted_ssn.present?
            demographics_hash[:dob] = demographics.dob.to_date if demographics.dob.present?

            demographics_hash
          end

          # Transforms all eligibilities belonging to an applicant to their CV3 representation
          # Includes associated evidences for each eligibility
          #
          # @param [IndividualMarket::Applicant] applicant The applicant whose eligibilities to transform
          # @return [Array<Hash>] Collection of transformed eligibility hashes
          def eligibilities(applicant)
            applicant.eligibilities.collect do |eligibility|
              {
                key: eligibility.key,
                title: eligibility.title,
                description: eligibility.description,
                current_state: eligibility.current_state,
                is_satisfied: eligibility.is_satisfied,
                determined_at: eligibility.determined_at,
                is_disqualified: eligibility.is_disqualified,
                disqualified_at: eligibility.disqualified_at,
                disqualified_reason: eligibility.disqualified_reason,
                evidences: evidences(eligibility),
                determinations: determinations(eligibility)
              }
            end
          end

          def immigration_information(applicant)
            immigration_information = applicant.immigration_information
            info_hash = {
              subject: immigration_information.subject,
              alien_number: immigration_information.alien_number,
              i94_number: immigration_information.i94_number,
              visa_number: immigration_information.visa_number,
              passport_number: immigration_information.passport_number,
              sevis_id: immigration_information.sevis_id,
              naturalization_number: immigration_information.naturalization_number,
              receipt_number: immigration_information.receipt_number,
              citizenship_number: immigration_information.citizenship_number,
              card_number: immigration_information.card_number,
              country_of_citizenship: immigration_information.country_of_citizenship,
              issuing_country: immigration_information.issuing_country,
              description: immigration_information.description,
              immigration_doc_statuses: immigration_information.immigration_doc_statuses
            }
            info_hash.merge!(expiration_date: immigration_information.expiration_date.to_datetime) if immigration_information.expiration_date.present?
            info_hash
          end

          def family_member_reference(applicant)
            return nil unless applicant.family_member.present?

            person_name = applicant.person_name
            demographics = applicant.demographics
            person_hbx_id = applicant.family_member.person.hbx_id

            {
              family_member_hbx_id: person_hbx_id,
              first_name: person_name.given_name,
              last_name: person_name.family_name,
              person_hbx_id: person_hbx_id,
              is_primary_family_member: applicant.is_primary_applicant,
              encrypted_ssn: encrypt(demographics.ssn),
              dob: demographics.dob
            }
          end

          # Transforms all evidences for an eligibility to their CV3 representation
          #
          # @param [Eligibilities::V3::Eligibility] eligibility The eligibility containing evidences
          # @return [Array<Hash>] Collection of transformed evidence hashes
          def evidences(eligibility)
            eligibility.evidences.collect do |evidence|
              {
                key: evidence.key,
                title: evidence.title,
                description: evidence.description,
                is_satisfied: evidence.is_satisfied,
                determined_at: evidence.determined_at,
                current_state: evidence.current_state,
                due_on: evidence.due_on
              }
            end
          end

          # Transforms all determinations for an eligibility to their CV3 representation
          #
          # @param [Eligibilities::V3::Eligibility] eligibility The eligibility containing determinations
          # @return [Array<Hash>] Collection of transformed determination hashes
          def determinations(eligibility)
            eligibility.determinations.collect do |determination|
              { key: determination.key, is_eligible: determination.is_eligible, bases: bases(determination) }
            end
          end

          # Transforms all bases for a determination to their CV3 representation
          #
          # @param [Eligibilities::V3::Determination] determination The determination containing bases
          # @return [Array<Hash>] Collection of transformed base hashes
          def bases(determination)
            determination.bases.collect do |basis|
              { basis_kind: basis.basis_kind, is_satisfied: basis.is_satisfied }
            end
          end

          # Transforms application attestation to its CV3 representation
          #
          # @param [IndividualMarket::Application] application The application containing the attestation
          # @return [Hash] The transformed attestation hash or empty hash if none exists
          def attestation(_application)
            # TODO: Implement attestation transformation
            # This is a placeholder for the attestation transformation logic
            {}
          end

          # Transforms all relationships in the application to their CV3 representation
          #
          # @param [IndividualMarket::Application] application The application containing relationships
          # @return [Array<Hash>] Collection of transformed relationship hashes
          def relationships(application)
            application.relationships.inject([]) do |result, relationship|
              relation = {
                kind: relationship.kind,
                source_reference: relationship_source(relationship),
                relative_reference: relationship_relative(relationship)
              }

              result << relation
              result
            end
          end

          # Gets the source applicant reference for a relationship
          #
          # @param [IndividualMarket::Relationship] relationship The relationship to process
          # @return [Hash] Hash containing the source applicant reference details
          def relationship_source(relationship)
            source = relationship.source
            relationship_source_relative(source)
          end

          # Gets the relative (target) applicant reference for a relationship
          #
          # @param [IndividualMarket::Relationship] relationship The relationship to process
          # @return [Hash] Hash containing the relative (target) applicant reference details
          def relationship_relative(relationship)
            relative = relationship.relative
            relationship_source_relative(relative)
          end

          # Builds a common format for applicant references in relationships
          #
          # @param [IndividualMarket::Applicant] applicant The applicant to reference
          # @return [Hash] Standardized hash with key applicant identification details
          def relationship_source_relative(applicant)
            person_name = applicant.person_name
            demographics = applicant.demographics
            {
              first_name: person_name.given_name,
              last_name: person_name.family_name,
              dob: demographics.dob,
              unique_id: applicant.id.to_s,
              encrypted_ssn: demographics.encrypted_ssn
            }
          end

          # Transforms all addresses for an applicant to their CV3 representation
          #
          # @param [IndividualMarket::Applicant] applicant The applicant whose addresses to transform
          # @return [Array<Hash>] Collection of transformed address hashes
          def addresses(applicant)
            applicant.addresses.collect do |address|
              {
                kind: address.kind,
                address_1: address.address_1,
                address_2: address.address_2,
                address_3: address.address_3,
                city: address.city,
                county: address.county,
                state: address.state,
                zip: address.zip,
                country_name: address.country_name,
                quadrant: address.quadrant
              }
            end
          end

          def encrypt(value)
            return nil unless value
            AcaEntities::Operations::Encryption::Encrypt.new.call({value: value}).value!
          end
        end
      end
    end
  end
end
