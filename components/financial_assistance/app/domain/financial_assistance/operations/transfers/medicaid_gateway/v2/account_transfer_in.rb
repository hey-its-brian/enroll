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
          # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/ClassLength
          class AccountTransferIn
            include ::FinancialAssistance::MeCountyHelper
            include Dry::Monads[:result, :do, :try]
            include ::ResourceRegistryHelper

            # @param [Hash] opts The options to transfer in a new Family & Application(persistence object)
            # @option opts [Hash] :params Atp payload params
            # @return [Dry::Monads::Result]
            def call(params)
              payload = yield load_data(params)
              payload = yield decrypt_ssns(payload)
              payload = yield load_missing_county_names(payload) if FinancialAssistanceRegistry.feature_enabled?(:load_county_on_inbound_transfer)
              family = yield build_family_with_primary_only(payload["family"])
              application_id = yield build_application(payload, family)
              application = yield find_application(application_id)
              _cancelled = yield cancel_previous_applications(application)
              _apps = yield build_applicants(payload, application, family)
              _applicants = yield fill_applicants_form(payload, application)
              _record = yield record(application)
              Success(application_id)
            end

            private

            def load_data(payload = {})
              Success(payload.to_h.deep_stringify_keys!)
            rescue StandardError => e
              Failure("load_data #{e}")
            end

            def decrypt_ssns(payload)
              payload["family"]["family_members"].each_with_index do |fm, i|
                ssn = fm["person"]["person_demographics"]["ssn"]
                decryption_result = decrypt_ssn(ssn)
                return decryption_result unless decryption_result.success?
                decrypted_ssn = decryption_result.value!
                payload["family"]["family_members"][i]["person"]["person_demographics"]["ssn"] = decrypted_ssn if decrypted_ssn.present?
                fm["person"]["person_relationships"].each_with_index do |relationship, ii|
                  rssn = relationship["relative"]["ssn"]
                  rdecryption_result = decrypt_ssn(rssn)
                  return rdecryption_result unless rdecryption_result.success?
                  rdecrypted_ssn = rdecryption_result.value!
                  payload["family"]["family_members"][i]["person"]["person_relationships"][ii]["relative"]["ssn"] = rdecrypted_ssn if rdecrypted_ssn.present?
                end
              end
              Success(payload)
            rescue StandardError => e
              Failure("decrypt ssns #{e}")
            end

            def decrypt_ssn(ssn)
              return Success(nil) unless ssn

              AcaEntities::Operations::Encryption::Decrypt.new.call({ value: ssn })
            rescue StandardError => e
              Failure("decrypt ssn #{e}")
            end

            def county_finder(zip)
              ::BenefitMarkets::Locations::CountyZip.where(zip: zip)
            end

            def find_specific_county(town_name)
              maine_counties_and_towns.detect { |key, _value| maine_counties_and_towns[key].include?(town_name) }&.first
            end

            def load_missing_county_names(payload)
              @zips_with_missing_counties = []
              @zips_with_multiple_counties = []

              payload.dig("family", "family_members").each do |person|
                person_addresses = person.dig("person", "addresses")
                populate_counties_for(person_addresses)
              end

              payload.dig("family", "magi_medicaid_applications")&.each do |application|
                application["applicants"]&.each do |applicant|
                  applicant_addresses = applicant["addresses"]
                  populate_counties_for(applicant_addresses)
                end
              end

              failure_message = "Unable to find county objects for zips #{@zips_with_missing_counties.uniq}" if @zips_with_missing_counties.present?
              failure_message = "Unable to match county for #{@zips_with_multiple_counties.uniq}, as multiple counties have this zip code." if @zips_with_multiple_counties.present?
              return Failure(failure_message) if failure_message.present?

              Success(payload)
            rescue StandardError => e
              Failure("load_missing_county_names #{e}")
            end

            def populate_counties_for(addresses)
              addresses.each do |address|
                next unless address["county"].blank?

                zip = address["zip"]
                county = county_finder(zip)
                address["county"] = county.first.county_name if county&.count == 1
                @zips_with_missing_counties << zip if county.blank?

                next unless county.count > 1
                town_name = address['city'].titleize
                county_name = find_specific_county(town_name)

                if county_name.present?
                  address['county'] = county_name
                else
                  @zips_with_multiple_counties << zip
                end
              end
            end

            def applicant_is_incarcerated(fm_hash, applicant_hash)
              demo = fm_hash.dig('person','person_demographics') || {}
              return demo['is_incarcerated'] unless demo['is_incarcerated'].nil?
              applicant_hash['is_incarcerated'] || false
            end

            def applicant_indian_tribe_member(fm_hash, applicant_hash)
              demo = fm_hash.dig('person','person_demographics') || {}
              return demo['indian_tribe_member'] unless demo['indian_tribe_member'].nil?
              applicant_hash['indian_tribe_member'] || false
            end

            def build_family_with_primary_only(family_hash)
              result = BuildFamilyAndCreateMember.new.call({family_hash: family_hash})
              return result if result.failure?

              @family = result.value!
              Success(@family)
            end

            def build_applicants(payload, application, family)
              sanitize_iap_hash = sanitize_applicant_params(payload, family)
              return sanitize_iap_hash unless sanitize_iap_hash.success?
              sanitized = sanitize_iap_hash.value!
              payload["family"]['magi_medicaid_applications'].first.except!('applicants').merge!(applicants: sanitized)
              applicants_results = sanitized.map do |applicant|
                ::FinancialAssistance::Operations::Applicant::Build.new.call(params: applicant.merge(application: application))
              end
              applicants_results.map do |result|
                return result if result.failure?
                applicant = application.applicants.build
                applicant.assign_attributes(result.success.to_h)
              end
              Success(application.applicants)
            end

            def build_application(payload, family)
              app = payload["family"]['magi_medicaid_applications'].first
              # years_to_renew needs to be merged with a hash rocket to properly merge with the existing years_to_renew key
              app_params = app.merge!(family_id: family.id, benchmark_product_id: BSON::ObjectId.new, "years_to_renew" => 5)
              if qhp_application_feature_enabled?
                app_params[:origin] = :data_import
                app_params[:generation_reason] = :manual
              end
              app_params["assistance_year"] = FinancialAssistanceRegistry[:enrollment_dates].setting(:application_year).item.constantize.new.call.value!.to_s
              ::FinancialAssistance::Operations::Application::Create.new.call(params: app_params.except('applicants').merge(applicants: []))
            rescue StandardError => e
              Failure("build_application: #{e}")
            end

            def same_address_with_primary(fm_hash, primary)
              return Failure("No matching family member") unless fm_hash.present?

              compare_keys = %w[address_1 address_2 city state zip]
              fm_homeless = fm_hash.dig('person','is_homeless')
              fm_temp_out = fm_hash.dig('person','is_temporarily_out_of_state')
              home_address = fm_hash.dig("person", "addresses")&.select { |add| add["kind"] == "home" }&.first
              primary_address_attributes = primary&.home_address&.attributes
              normalized_home_address = compare_keys.index_with { |k| home_address[k].to_s }
              normalized_primary_address = compare_keys.index_with { |k| primary_address_attributes&.[](k).to_s }
              same = fm_homeless == primary.is_homeless? &&
                     fm_temp_out == primary.is_temporarily_out_of_state? &&
                     normalized_home_address == normalized_primary_address

              Success(same)
            rescue StandardError => e
              Failure("same_address_with_primary: #{e}")
            end

            def sanitize_applicant_params(payload, family)
              sanitize_params = []
              primary = family.primary_person
              iap_hash = payload["family"]['magi_medicaid_applications'].first
              family_members_payload = payload.dig('family', 'family_members') || []
              applicants = iap_hash['applicants']

              applicants.each do |applicant_hash|
                fm_hash = find_matching_family_member(family_members_payload, applicant_hash)
                is_primary = fm_hash&.dig('is_primary_applicant') == true
                demographic_hash = fm_hash&.dig('person', 'person_demographics')
                address_result = same_address_with_primary(fm_hash, primary)

                return address_result unless address_result.success?

                context = {
                  applicant_hash: applicant_hash,
                  fm_hash: fm_hash,
                  is_primary: is_primary,
                  primary: primary,
                  demographic_hash: demographic_hash,
                  address_result: address_result,
                  family: family
                }
                sanitize_params << build_applicant_params(context)
              end

              Success(sanitize_params)
            rescue StandardError => e
              Failure("sanitize_applicant_params: #{e}")
            end

            def find_matching_family_member(family_members, applicant)
              family_members.detect do |fm|
                Date.parse(fm.dig('person', 'person_demographics', 'dob')) == applicant.dig('demographic', 'dob').to_date &&
                  fm.dig('person', 'person_name', 'first_name').casecmp(applicant.dig('name', 'first_name')).zero? &&
                  fm.dig('person', 'person_name', 'last_name').casecmp(applicant.dig('name', 'last_name')).zero?
              end
            end

            def build_applicant_params(context)
              # Destructure the context object to get individual variables
              applicant_hash = context[:applicant_hash]
              fm_hash = context[:fm_hash]
              is_primary = context[:is_primary]
              primary = context[:primary]
              demographic_hash = context[:demographic_hash]
              address_result = context[:address_result]
              family = context[:family]

              citizen_status_info = applicant_hash['citizenship_immigration_status_information']
              foster_info = applicant_hash['foster_care']
              phones = valid_applicant_phones(applicant_hash['phones'])
              no_ssn = fm_hash&.dig('person', 'person_demographics', 'no_ssn')

              {
                # Identity attributes
                family_member_id: is_primary ? family.primary_applicant.id : nil,
                relationship: fm_hash&.dig('person', 'person_relationships', 0, 'kind'),
                person_hbx_id: is_primary ? primary.hbx_id : nil,
                ext_app_id: applicant_hash['person_hbx_id'],

                # Name attributes
                **extract_name_attributes(applicant_hash['name']),

                # Demographics
                ssn: fm_hash&.dig('person', 'person_demographics', 'ssn'),
                no_ssn: no_ssn ? "1" : "0",
                **extract_demographic_attributes(applicant_hash['demographic']),

                # Address related
                same_with_primary: address_result.value!,

                # Special statuses
                is_incarcerated: applicant_is_incarcerated(fm_hash, applicant_hash),
                **extract_attestation_attributes(applicant_hash['attestation']),

                # Primary status
                is_primary_applicant: applicant_hash['is_primary_applicant'],
                native_american_information: applicant_hash['native_american_information'],

                # Citizenship attributes
                **extract_citizenship_attributes(citizen_status_info),

                # Roles
                is_consumer_role: true, # Hard-coded to true
                is_resident_role: applicant_hash['is_resident_role'],
                is_applying_coverage: applicant_hash['is_applying_coverage'],
                is_consent_applicant: applicant_hash['is_consent_applicant'],

                # VLP attributes
                **extract_vlp_attributes(applicant_hash),

                # Tax attributes
                **extract_tax_attributes(applicant_hash),

                # Student attributes
                **extract_student_attributes(applicant_hash['student']),

                # Special status attributes
                is_refugee: applicant_hash['is_refugee'],
                is_trafficking_victim: applicant_hash['is_trafficking_victim'],

                # Foster care attributes
                **extract_foster_care_attributes(foster_info),

                # Pregnancy attributes
                **extract_pregnancy_attributes(applicant_hash['pregnancy_information']),

                # Status and eligibility attributes
                is_subject_to_five_year_bar: applicant_hash['is_refugee'],
                is_five_year_bar_met: applicant_hash['is_refugee'],
                is_forty_quarters: applicant_hash['is_forty_quarters'],
                is_ssn_applied: applicant_hash['is_ssn_applied'],
                non_ssn_apply_reason: applicant_hash['non_ssn_apply_reason'],
                moved_on_or_after_welfare_reformed_law: applicant_hash['moved_on_or_after_welfare_reformed_law'],
                is_currently_enrolled_in_health_plan: applicant_hash['is_currently_enrolled_in_health_plan'],

                # Help attributes
                has_daily_living_help: applicant_hash['has_daily_living_help'],
                need_help_paying_bills: applicant_hash['need_help_paying_bills'],

                # Income attributes
                has_job_income: applicant_hash['has_job_income'],
                has_self_employment_income: applicant_hash['has_self_employment_income'],
                has_unemployment_income: applicant_hash['has_unemployment_income'],
                has_other_income: applicant_hash['has_other_income'],
                has_deductions: applicant_hash['has_deductions'],

                # Coverage attributes
                has_enrolled_health_coverage: applicant_hash['has_enrolled_health_coverage'],
                has_eligible_health_coverage: applicant_hash['has_eligible_health_coverage'],

                # Contact information
                addresses: applicant_hash['addresses'],
                emails: applicant_hash['emails'],
                phones: phones,

                # Financial information
                incomes: applicant_hash['incomes'],
                benefits: applicant_hash['benefits'],
                deductions: applicant_hash['deductions'],

                # Additional attributes
                is_medicare_eligible: applicant_hash['is_medicare_eligible'],
                has_insurance: applicant_hash['has_insurance'],
                has_state_health_benefit: applicant_hash['has_state_health_benefit'],
                had_prior_insurance: applicant_hash['had_prior_insurance'],
                age_of_applicant: applicant_hash['age_of_applicant'],
                hours_worked_per_week: applicant_hash['hours_worked_per_week'],

                # Tribal information
                indian_tribe_member: applicant_indian_tribe_member(fm_hash, applicant_hash),
                tribal_id: demographic_hash["tribal_id"],
                tribal_name: demographic_hash["tribal_name"],
                tribal_state: demographic_hash["tribal_state"],
                tribe_codes: demographic_hash["tribe_codes"] || [],

                # Transfer info
                transfer_referral_reason: applicant_hash['transfer_referral_reason']
              }
            end

            # Helper methods to extract attribute groups
            def extract_name_attributes(name_hash)
              {
                first_name: name_hash['first_name'],
                middle_name: name_hash['middle_name'],
                last_name: name_hash['last_name'],
                full_name: name_hash['full_name'],
                name_sfx: name_hash['name_sfx'],
                name_pfx: name_hash['name_pfx'],
                alternate_name: name_hash['alternate_name']
              }
            end

            def extract_demographic_attributes(demographic_hash)
              {
                gender: demographic_hash['gender'],
                dob: demographic_hash['dob'],
                ethnicity: demographic_hash['ethnicity'] || [],
                race: demographic_hash['race'],
                is_veteran_or_active_military: demographic_hash['is_veteran_or_active_military'],
                is_vets_spouse_or_child: demographic_hash['is_vets_spouse_or_child']
              }
            end

            def extract_attestation_attributes(attestation_hash)
              {
                is_physically_disabled: attestation_hash['is_self_attested_disabled'],
                is_self_attested_disabled: attestation_hash['is_self_attested_disabled'],
                is_self_attested_blind: attestation_hash['is_self_attested_blind'],
                is_self_attested_long_term_care: attestation_hash['is_self_attested_long_term_care']
              }
            end

            def extract_citizenship_attributes(citizenship_info)
              {
                citizen_status: citizenship_info ? citizenship_info['citizen_status'] : nil,
                is_resident_post_092296: citizenship_info ? citizenship_info['is_resident_post_092296'] : nil,
                is_lawful_presence_self_attested: citizenship_info ? citizenship_info['is_lawful_presence_self_attested'] : nil
              }
            end

            def extract_vlp_attributes(applicant_hash)
              {
                vlp_subject: applicant_hash['vlp_subject'],
                alien_number: applicant_hash['alien_number'],
                i94_number: applicant_hash['i94_number'],
                visa_number: applicant_hash['visa_number'],
                passport_number: applicant_hash['passport_number'],
                sevis_id: applicant_hash['sevis_id'],
                naturalization_number: applicant_hash['naturalization_number'],
                receipt_number: applicant_hash['receipt_number'],
                citizenship_number: applicant_hash['citizenship_number'],
                card_number: applicant_hash['card_number'],
                country_of_citizenship: applicant_hash['country_of_citizenship'],
                vlp_description: applicant_hash['vlp_description'],
                expiration_date: applicant_hash['expiration_date'],
                issuing_country: applicant_hash['issuing_country']
              }
            end

            def extract_tax_attributes(applicant_hash)
              {
                is_required_to_file_taxes: applicant_hash['is_required_to_file_taxes'],
                tax_filer_kind: applicant_hash['tax_filer_kind'],
                is_joint_tax_filing: applicant_hash['is_joint_tax_filing'],
                is_claimed_as_tax_dependent: applicant_hash['is_claimed_as_tax_dependent'],
                claimed_as_tax_dependent_by: applicant_hash['claimed_as_tax_dependent_by']
              }
            end

            def extract_student_attributes(student_hash)
              {
                is_student: student_hash['is_student'],
                student_kind: student_hash['student_kind'],
                student_school_kind: student_hash['student_school_kind'],
                student_status_end_on: student_hash['student_status_end_on']
              }
            end

            def extract_foster_care_attributes(foster_info)
              {
                is_former_foster_care: foster_info ? foster_info['is_former_foster_care'] : nil,
                age_left_foster_care: foster_info ? foster_info['age_left_foster_care'] : nil,
                foster_care_us_state: foster_info ? foster_info['foster_care_us_state'] : nil,
                had_medicaid_during_foster_care: foster_info ? foster_info['had_medicaid_during_foster_care'] : nil
              }
            end

            def extract_pregnancy_attributes(pregnancy_info)
              {
                is_pregnant: pregnancy_info['is_pregnant'],
                is_enrolled_on_medicaid: pregnancy_info['is_enrolled_on_medicaid'],
                is_post_partum_period: pregnancy_info['is_post_partum_period'],
                children_expected_count: pregnancy_info['expected_children_count'],
                pregnancy_due_on: pregnancy_info['pregnancy_due_on'],
                pregnancy_end_on: pregnancy_info['pregnancy_end_on']
              }
            end

            def valid_applicant_phones(phones)
              phones.map do |phone|
                valid_phone_params = phone.slice("kind", "country_code", "area_code", "number", "extension", "primary", "full_phone_number")
                invalid_phone = FinancialAssistance::Locations::Phone.new(valid_phone_params).invalid? || phone['full_phone_number']&.first == '0' || phone['area_code']&.first == '0'
                next if invalid_phone

                valid_phone_params
              end.compact
            end

            def find_application(id)
              applications = FinancialAssistance::Application.where(id: id)
              return Failure("Application with id #{id} not found") unless applications.any?
              Success(applications.first)
            end

            # Cancels previous draft applications when a new one is created
            # @param [FinancialAssistance::Application] application The newly created draft application
            # @return [Dry::Monads::Result::Success] Success monad with a message
            def cancel_previous_applications(application)
              if qhp_application_feature_enabled?
                ::FinancialAssistance::Operations::Applications::CancelPreviousApplications.new.call(
                  application: application
                )
                Success('Previous applications cancelled successfully')
              else
                # Returns success as we don't want to block the account transfer in
                # when the feature flag is disabled
                Success('Cannot cancel applications as feature flag is disabled')
              end
            end

            def fill_applicants_form(payload, application) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
              applications = payload["family"]['magi_medicaid_applications'].first
              applications[:applicants].each do |applicant|
                persisted_applicant = application.applicants.where(first_name: /^#{applicant[:first_name]}$/i, last_name: /^#{applicant[:last_name]}$/i, dob: applicant[:dob]).first
                return Failure("No matching applicant") unless persisted_applicant.present?
                claimed_by = application.applicants.where(ext_app_id: applicant[:claimed_as_tax_dependent_by]).first
                persisted_applicant.is_physically_disabled = applicant[:is_physically_disabled]
                persisted_applicant.is_self_attested_blind = applicant[:is_self_attested_blind]
                persisted_applicant.is_self_attested_disabled = applicant[:is_self_attested_disabled]
                persisted_applicant.is_required_to_file_taxes = applicant[:is_required_to_file_taxes]
                persisted_applicant.tax_filer_kind = applicant[:tax_filer_kind]
                persisted_applicant.is_joint_tax_filing = applicant[:is_joint_tax_filing]
                persisted_applicant.is_claimed_as_tax_dependent = applicant[:is_claimed_as_tax_dependent]
                persisted_applicant.claimed_as_tax_dependent_by = claimed_by ? claimed_by.id : nil

                persisted_applicant.is_student = applicant[:is_student]
                persisted_applicant.student_kind = applicant[:student_kind]
                persisted_applicant.student_school_kind = applicant[:student_school_kind]
                persisted_applicant.student_status_end_on = applicant[:student_status_end_on]

                persisted_applicant.is_refugee = applicant[:is_refugee]
                persisted_applicant.is_trafficking_victim = applicant[:is_trafficking_victim]

                persisted_applicant.is_former_foster_care = applicant[:is_former_foster_care]
                persisted_applicant.age_left_foster_care = applicant[:age_left_foster_care]
                persisted_applicant.foster_care_us_state = applicant[:foster_care_us_state]
                persisted_applicant.had_medicaid_during_foster_care = applicant[:had_medicaid_during_foster_care]

                persisted_applicant.is_pregnant = applicant[:is_pregnant]
                persisted_applicant.is_enrolled_on_medicaid = applicant[:is_enrolled_on_medicaid]
                persisted_applicant.is_post_partum_period = applicant[:is_post_partum_period]
                persisted_applicant.children_expected_count = applicant[:children_expected_count]
                persisted_applicant.pregnancy_due_on = applicant[:pregnancy_due_on]
                persisted_applicant.pregnancy_end_on = applicant[:pregnancy_end_on]

                persisted_applicant.is_subject_to_five_year_bar = applicant[:is_subject_to_five_year_bar]
                persisted_applicant.is_five_year_bar_met = applicant[:is_five_year_bar_met]
                persisted_applicant.is_forty_quarters = applicant[:is_forty_quarters]
                persisted_applicant.is_ssn_applied = applicant[:is_ssn_applied]
                persisted_applicant.non_ssn_apply_reason = applicant[:non_ssn_apply_reason]
                persisted_applicant.moved_on_or_after_welfare_reformed_law = applicant[:moved_on_or_after_welfare_reformed_law]
                persisted_applicant.is_currently_enrolled_in_health_plan = applicant[:is_currently_enrolled_in_health_plan]
                persisted_applicant.has_daily_living_help = applicant[:has_daily_living_help]
                persisted_applicant.need_help_paying_bills = applicant[:need_help_paying_bills]
                persisted_applicant.has_job_income = applicant[:has_job_income]
                persisted_applicant.has_self_employment_income = applicant[:has_self_employment_income]
                persisted_applicant.has_unemployment_income = applicant[:has_unemployment_income]
                persisted_applicant.has_other_income = applicant[:has_other_income]
                persisted_applicant.has_deductions = applicant[:has_deductions]
                persisted_applicant.has_enrolled_health_coverage = applicant[:has_enrolled_health_coverage]
                persisted_applicant.has_eligible_health_coverage = applicant[:has_eligible_health_coverage]
                persisted_applicant.incomes = applicant[:incomes]
                persisted_applicant.benefits = applicant[:benefits].first.nil? ? [] : applicant[:benefits].compact
                persisted_applicant.deductions = applicant[:deductions].collect {|d| d.except("amount_tax_exempt", "is_projected")}
                persisted_applicant.is_medicare_eligible = applicant[:is_medicare_eligible]
                persisted_applicant.transfer_referral_reason = applicant[:transfer_referral_reason]
                ::FinancialAssistance::Applicant.skip_callback(:update, :after, :propagate_applicant, raise: false) # TODO: remove raise: false after FFE migration
                ::FinancialAssistance::Relationship.skip_callback(:save, :after, :propagate_applicant)
                persisted_applicant.save(validate: false)
                persisted_applicant.relationships.each do |rel|
                  rel.save(validate: false)
                end
                ::FinancialAssistance::Applicant.set_callback(:update, :after, :propagate_applicant, raise: false) # TODO: remove raise: false after FFE migration
                ::FinancialAssistance::Relationship.set_callback(:save, :after, :propagate_applicant)
              end
              Success("Successfully transferred in account")
            rescue Mongoid::Errors::Validations => e
              Failure("Fill applicant form validation: #{e.summary}")
            rescue StandardError => e
              Failure("Fill applicant form: #{e}")
            end

            def record(application)
              result = Try do
                application.set(transferred_at: DateTime.now.utc)
              end
              result.success? ? Success("recorded transferred_at") : Failure("could not set transferred_at")
            end
            # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/ClassLength
          end
        end
      end
    end
  end
end
