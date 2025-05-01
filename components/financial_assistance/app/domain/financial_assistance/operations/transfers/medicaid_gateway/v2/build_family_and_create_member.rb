# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'aca_entities/operations/encryption/decrypt'

module FinancialAssistance
  module Operations
    module Transfers
      module MedicaidGateway
        module V2
          # This Operation creates a new family with only primary member and application in draft status
          # Operation receives ATP payload from medicaid gateway
          class BuildFamilyAndCreateMember
            include Dry::Monads[:result, :do, :try]

            def call(params)
              validated_params = yield validate(params)
              result = yield build_family_with_primary_only(validated_params[:family_hash])

              Success(result)
            end

            private

            def validate(params)
              return Failure('Family member should not be blank') if params[:family_hash].blank?
              return Failure('Family member should be a hash') unless params[:family_hash].is_a?(Hash)

              Success(params)
            end

            def build_family_with_primary_only(family_hash)
              found_family_result = find_family(family_hash)
              return found_family_result unless found_family_result.success?
              found_family = found_family_result.value!

              if found_family.present?
                Success(found_family)
              else
                @family = ::Family.new(family_hash.except('hbx_id', 'foreign_keys', 'broker_accounts',
                                                          'magi_medicaid_applications', 'family_members',
                                                          'households', 'ext_app_id'))

                # Only process primary applicant
                primary_member = family_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
                return Failure("No primary applicant found in payload") if primary_member.blank?

                fm_result = create_member(primary_member)
                return fm_result unless fm_result.success?

                Success(@family)
              end
            rescue Mongoid::Errors::Validations => e
              Failure("build_family validation: #{e.summary}")
            rescue StandardError => e
              Failure("build_family: #{e}")
            end

            def create_member(family_member_hash)
              person_params_result = sanitize_person_params(family_member_hash)
              return person_params_result unless person_params_result.success?
              person_params = person_params_result.value!
              updated_person_params = fetch_updated_person_params(person_params)
              person_result = create_or_update_person(updated_person_params)
              if person_result.success?
                @person = person_result.success
                fam_result = create_or_update_family_member(@person, @family, family_member_hash)
                return fam_result unless fam_result.success?
                @family_member = fam_result.value!
                consumer_role_params = family_member_hash['person']['consumer_role']
                create_or_update_consumer_role(consumer_role_params.merge(is_consumer_role: true), @family_member)
                create_or_update_vlp_documents(consumer_role_params['vlp_documents'], @person) if consumer_role_params['vlp_documents']
                Success(@person.consumer_role)
              else
                first_name = family_member_hash['person']['person_name']['first_name']
                last_name = family_member_hash['person']['person_name']['last_name']
                Failure("Failed to create or update person #{first_name} #{last_name} due to: #{person_result.failure}")
              end
            rescue StandardError => e
              Failure("create_member: #{e}")
            end

            def find_family(family_hash)
              primary_applicant = family_hash['family_members'].select { |a| a["is_primary_applicant"] == true}.first
              return Failure("No primary applicant found in payload") if primary_applicant.blank?

              person_params_result = sanitize_person_params(primary_applicant)
              return person_params_result if person_params_result.failure?
              person_params = person_params_result.value!
              person = fetch_person(person_params)
              return Success(nil) if person.blank?

              Success(person.primary_family)
            rescue StandardError => e
              Failure("find family error #{e}")
            end

            def sanitize_person_params(family_member_hash)
              person_hash = family_member_hash['person']
              consumer_role_hash = person_hash["consumer_role"]
              build_person_hash(person_hash, consumer_role_hash)
            rescue StandardError => e
              Failure("sanitize_person_params: #{e}")
            end

            def build_person_hash(person_hash, consumer_role_hash)
              phash = {}.merge(
                basic_person_attributes(person_hash),
                demographics_attributes(person_hash['person_demographics']),
                tribal_attributes(person_hash['person_demographics']),
                health_attributes(person_hash['person_health']),
                status_attributes(person_hash),
                contact_attributes(person_hash)
              )

              unless consumer_role_hash['is_applying_coverage']
                phash[:race] = nil
                phash[:ethnicity] = []
                phash[:is_incarcerated] = nil
              end

              Success(phash)
            rescue StandardError => e
              Failure("build person hash #{e}")
            end

            def basic_person_attributes(person_hash)
              {
                first_name: person_hash['person_name']['first_name'],
                last_name: person_hash['person_name']['last_name'],
                middle_name: person_hash['person_name']['middle_name'],
                full_name: person_hash['person_name']['full_name'],
                individual_market_transitions: person_hash['individual_market_transitions'],
                verification_types: person_hash['verification_types']
              }
            end

            def demographics_attributes(person_demographics)
              {
                ssn: person_demographics['ssn'],
                no_ssn: transform_no_ssn(person_demographics['ssn']),
                gender: person_demographics['gender'],
                dob: person_demographics['dob'],
                date_of_death: person_demographics['date_of_death'],
                dob_check: person_demographics['dob_check'],
                ethnicity: person_demographics['ethnicity'] || [],
                is_incarcerated: person_demographics['is_incarcerated'],
                language_code: person_demographics['language_code']
              }
            end

            def tribal_attributes(person_demographics)
              {
                indian_tribe_member: person_demographics['indian_tribe_member'],
                tribal_id: person_demographics['tribal_id'],
                tribal_name: person_demographics['tribal_name'],
                tribal_state: person_demographics['tribal_state'],
                tribe_codes: person_demographics['tribe_codes'] || []
              }
            end

            def health_attributes(person_health)
              {
                is_tobacco_user: person_health['is_tobacco_user'],
                is_physically_disabled: person_health['is_physically_disabled']
              }
            end

            def status_attributes(person_hash)
              {
                is_homeless: person_hash['is_homeless'],
                is_temporarily_out_of_state: person_hash['is_temporarily_out_of_state'],
                age_off_excluded: person_hash['age_off_excluded'],
                is_active: person_hash['is_active'],
                is_disabled: person_hash['is_disabled'],
                race: person_hash['race']
              }
            end

            def contact_attributes(person_hash)
              {
                addresses: person_hash['addresses'],
                emails: person_hash['emails'],
                phones: valid_person_phones(person_hash['phones'])
              }
            end

            def transform_no_ssn(ssn)
              ssn.present? ? '0' : '1'
            end

            def valid_person_phones(phones)
              phones.map do |phone|
                valid_phone_params = phone.slice("kind", "country_code", "area_code", "number", "extension", "primary", "full_phone_number")
                invalid_phone = Phone.new(valid_phone_params).invalid? || phone['full_phone_number']&.first == '0' || phone['area_code']&.first == '0'
                next if invalid_phone

                valid_phone_params
              end.compact
            end

            def fetch_person(person_params)
              match_criteria, records = ::Operations::People::Match.new.call({:dob => person_params[:dob],
                                                                              :last_name => person_params[:last_name],
                                                                              :first_name => person_params[:first_name],
                                                                              :ssn => person_params[:ssn]})
              return unless records.present?
              return unless [:ssn_present, :dob_present].include?(match_criteria)
              return if match_criteria == :dob_present && person_params[:ssn].present? && records.first.ssn != person_params[:ssn]

              records.first
            end

            def fetch_updated_person_params(person_params)
              person = fetch_person(person_params)
              return person_params if person.blank?

              if person_params[:indian_tribe_member].nil?
                attributes_to_exclude = [:tribal_name, :tribal_state, :tribal_id,
                                         :tribe_codes,
                                         :indian_tribe_member]
              end
              person_params.except(*attributes_to_exclude)
            end

            def create_or_update_person(person_params)
              ::Operations::People::CreateOrUpdate.new.call(params: person_params)
            rescue StandardError => e
              Failure("create_or_update_person: #{e}")
            end

            def create_or_update_consumer_role(applicant_params, family_member)
              return unless applicant_params[:is_consumer_role]
              # assign_citizen_status
              params = applicant_params.except("lawful_presence_determination")
              merge_params = params.merge(citizen_status: applicant_params["lawful_presence_determination"]["citizen_status"])
              ::Operations::People::CreateOrUpdateConsumerRole.new.call(
                params: {
                  applicant_params: merge_params,
                  family_member: family_member,
                  optimistic_upstream_coverage_attestation_interpretation: EnrollRegistry.feature_enabled?(:optimistic_upstream_coverage_attestation)
                }
              )
            rescue StandardError => e
              Failure("create_or_update_consumer_role: #{e}")
            end

            def create_or_update_family_member(person, family, family_member_hash)
              family_member = family.family_members.detect { |fm| fm.person_id.to_s == person.id.to_s }

              return Success(family_member) if family_member && (family_member_hash.key?(:is_active) ? family_member.is_active == family_member_hash[:is_active] : true)

              rel_result = create_or_update_relationship(person, family, family_member_hash['person']['person_relationships'][0]['kind'])
              return rel_result unless rel_result.success?

              fm_attr = { is_primary_applicant: family_member_hash['is_primary_applicant'],
                          is_consent_applicant: family_member_hash['is_consent_applicant'],
                          is_coverage_applicant: family_member_hash['is_coverage_applicant'],
                          is_active: family_member_hash['is_active'] }
              family_member = family.add_family_member(person, fm_attr)
              family_member.save!

              Success(family_member)
            rescue Mongoid::Errors::Validations => e
              first_name = family_member_hash['person']['person_name']['first_name']
              last_name = family_member_hash['person']['person_name']['last_name']
              Failure("Failed create_or_update_family_member validation for #{first_name} #{last_name} due to: #{e.summary}")
            rescue StandardError => e
              Failure("create_or_update_family_member: #{e}")
            end

            def create_or_update_vlp_documents(vlp_documents, person)
              failed_results = vlp_documents.each_with_object([]) do |vlp_document, failures|
                result = ::Operations::People::CreateOrUpdateVlpDocument.new.call(params: { applicant_params: vlp_document, person: person })
                failures << result.failure unless result.success?
              end
              Failure("Failed to create or update VLP document(s): #{failures}") if failed_results.present?
            rescue StandardError => e
              Failure("create_or_update_vlp_documents: #{e}")
            end

            def create_or_update_relationship(person, family, relationship_kind)
              if relationship_kind == "self"
                primary_self_relationship = PersonRelationship.new({
                                                                     :kind => relationship_kind,
                                                                     :relative_id => person.id
                                                                   })
                person.person_relationships << primary_self_relationship
                primary_self_relationship.save!
                return Success("created primary relationship to self")
              end

              existing_relationship = family.primary_person.person_relationships.detect { |rel| rel.relative_id.to_s == person.id.to_s }
              return Success("checked relationship") if existing_relationship && existing_relationship.kind == relationship_kind

              relationships = family.primary_person.ensure_relationship_with(person, relationship_kind)
              relationships&.map(&:save!)
              Success("created relationship")
            rescue StandardError => e
              Failure("create_or_update_relationship: #{e}")
            end
          end
        end
      end
    end
  end
end
