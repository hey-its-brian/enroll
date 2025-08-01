# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module AsyncMigrations
    module Handlers
      # This module contains logic related to copying financial assistance applications without persisting them.
      module FAApplication
        # This Operation builds a new application for a given application identifier(BSON ID),
        class CopyWithoutPersisting < ::FinancialAssistance::Operations::Applications::Copy
          include Dry::Monads[:do, :result]
          include AddressValidator
          include I18n
          include ::ResourceRegistryHelper

          def fetch_active_fms_applicant_params(_application)
            Success(nil)
          end

          def set_attribute_reader(_application, _active_fms_applicant_params)
            Success(nil)
          end

          def fetch_applicant_params(source_applicant, _nothing)
            source_appli_params = source_applicant.attributes.slice(:name_pfx, :first_name, :middle_name, :last_name, :name_sfx, :encrypted_ssn, :gender, :dob, :is_primary_applicant,
                                                                    :is_incarcerated, :is_disabled, :ethnicity, :race, :indian_tribe_member, :tribal_id, :language_code, :no_dc_address,
                                                                    :is_homeless, :is_temporarily_out_of_state, :immigration_doc_statuses, :no_ssn, :citizen_status, :is_consumer_role,
                                                                    :is_resident_role, :same_with_primary, :is_applying_coverage, :is_tobacco_user, :vlp_document_id, :vlp_subject,
                                                                    :alien_number, :i94_number, :visa_number, :passport_number, :sevis_id, :naturalization_number, :receipt_number,
                                                                    :citizenship_number, :card_number, :country_of_citizenship, :vlp_description, :expiration_date, :issuing_country,
                                                                    :is_consent_applicant, :assisted_income_validation, :assisted_mec_validation, :assisted_income_reason,
                                                                    :assisted_mec_reason, :aasm_state, :person_hbx_id, :ext_app_id, :family_member_id, :has_fixed_address, :is_living_in_state,
                                                                    :is_required_to_file_taxes, :is_filing_as_head_of_household, :tax_filer_kind, :is_joint_tax_filing, :is_claimed_as_tax_dependent,
                                                                    :is_physically_disabled, :has_income_verification_response, :has_mec_verification_response, :is_medicare_eligible, :is_student,
                                                                    :student_kind, :student_school_kind, :student_status_end_on, :is_self_attested_blind, :is_self_attested_disabled,
                                                                    :is_self_attested_long_term_care, :is_veteran, :is_refugee, :is_trafficking_victim, :is_former_foster_care, :age_left_foster_care,
                                                                    :foster_care_us_state, :had_medicaid_during_foster_care, :is_pregnant, :is_enrolled_on_medicaid, :is_post_partum_period,
                                                                    :children_expected_count, :pregnancy_due_on, :pregnancy_end_on, :is_primary_caregiver, :is_subject_to_five_year_bar,
                                                                    :is_five_year_bar_met, :net_annual_income, :is_forty_quarters, :is_ssn_applied, :non_ssn_apply_reason, :moved_on_or_after_welfare_reformed_law,
                                                                    :is_veteran_or_active_military, :is_spouse_or_dep_child_of_veteran_or_active_military, :is_currently_enrolled_in_health_plan,
                                                                    :has_daily_living_help, :need_help_paying_bills, :is_resident_post_092296, :is_vets_spouse_or_child, :has_job_income,
                                                                    :has_self_employment_income, :has_other_income, :has_unemployment_income, :has_deductions, :has_enrolled_health_coverage,
                                                                    :has_eligible_health_coverage, :has_american_indian_alaskan_native_income, :medicaid_chip_ineligible, :immigration_status_changed,
                                                                    :health_service_through_referral, :health_service_eligible, :tribal_state, :tribal_name, :tribe_codes, :is_medicaid_cubcare_eligible,
                                                                    :has_eligible_medicaid_cubcare, :medicaid_cubcare_due_on, :has_eligibility_changed, :has_household_income_changed,
                                                                    :person_coverage_end_on, :has_dependent_with_coverage, :dependent_job_end_on, :transfer_referral_reason,
                                                                    :five_year_bar_applies, :five_year_bar_met, :qualified_non_citizen, :age_off_excluded, :eligibility_determination_id,
                                                                    :is_eligible_for_non_magi_reasons, :magi_medicaid_category, :medicaid_household_size, :magi_medicaid_monthly_household_income,
                                                                    :magi_medicaid_monthly_income_limit, :magi_as_percentage_of_fpl, :csr_percent_as_integer, :csr_eligibility_kind,
                                                                    :benchmark_premiums, :contact_method, :language_preference, :is_ia_eligible, :is_csr_eligible, :is_medicaid_chip_eligible,
                                                                    :is_non_magi_medicaid_eligible, :is_totally_ineligible, :is_without_assistance, :is_magi_medicaid, :is_gap_filling, :emails, :phones, :addresses)

            source_appli_params.deep_symbolize_keys
          end

          def build_new_emails(new_applicant, source_applicant_params)
            return if source_applicant_params[:emails].blank?
            source_applicant_params[:emails].each do |email_params|
              new_applicant.build_new_email(email_params.slice(:kind, :address))
            end
          end

          def build_new_phones(new_applicant, source_applicant_params)
            return if source_applicant_params[:phones].blank?
            source_applicant_params[:phones].each do |phone_params|
              new_applicant.build_new_phone(phone_params.slice(:kind, :country_code, :area_code, :number, :extension, :primary, :full_phone_number))
            end
          end

          def build_new_addresses(new_applicant, source_applicant_params)
            return if source_applicant_params[:addresses].blank?
            source_applicant_params[:addresses].each do |address_params|
              new_applicant.build_new_address(address_params.slice(:kind, :address_1, :address_2, :address_3, :city, :county, :state, :zip, :country_name, :quadrant))
            end
          end

          def build_applicant_embeded_documents(source_applicant, new_applicant, source_applicant_params)
            build_new_addresses(new_applicant, source_applicant_params)
            build_new_phones(new_applicant, source_applicant_params)
            build_new_emails(new_applicant, source_applicant_params)
            build_new_incomes(source_applicant, new_applicant)
            build_new_deductions(source_applicant, new_applicant)
            build_new_benefits(source_applicant, new_applicant)
            build_member_determinations(source_applicant, new_applicant)
          end

          def build_member_determinations(source_applicant, new_applicant)
            return if source_applicant.member_determinations.blank?
            source_applicant.member_determinations.each do |old_member_determination|
              md = new_applicant.member_determinations.build(old_member_determination.attributes.slice(:kind, :criteria_met, :determination_reasons))
              md.eligibility_overrides = old_member_determination.eligibility_overrides.map do |override|
                override.attributes.slice(:override_rule, :override_applied)
              end
            end
          end

          def build_application_embeded_documents(source_application, new_app, _active_fms_applicant_params)
            build_applicants(source_application, new_app)
            build_eligibility_determinations(source_application, new_app)
            build_relationships(source_application, new_app)
          end

          def build_applicants(source_application, new_app)
            source_application.applicants.each do |source_applicant|
              source_applicant_params = fetch_applicant_params(source_applicant, nil)
              new_applicant = new_app.build_new_applicant(source_applicant_params.except(:emails, :phones, :addresses))
              build_applicant_embeded_documents(source_applicant, new_applicant, source_applicant_params)
            end
          end

          def build_relationships(source_application, new_app)
            copy_relationships_from_source_app(source_application, new_app)
          end

          def build_eligibility_determinations(source_application, new_app)
            source_application.eligibility_determinations.each do |eligibility_determination|
              params = fetch_eligibility_determination_params(eligibility_determination)
              new_eligibility_determination = new_app.eligibility_determinations.build(params)

              new_applicants = new_app.applicants.where(eligibility_determination_id: eligibility_determination.id)
              new_applicants.each do |applicant|
                applicant.assign_attributes(eligibility_determination_id: new_eligibility_determination.id)
              end
            end
          end

          def fetch_eligibility_determination_params(eligibility_determination)
            eligibility_determination.attributes.slice(
              :max_aptc, :aptc_csr_annual_household_income, :aptc_annual_income_limit, :csr_annual_income_limit, :yearly_expected_contribution, :hbx_assigned_id, :determined_at, :effective_starting_on, :is_eligibility_determined, :source
            )
          end

          # Overrides the method to build a new application without persisting it.
          def copy_application(application, active_fms_applicant_params)
            draft_app = build_application(application, active_fms_applicant_params)

            if draft_app.valid?
              Success(draft_app)
            else
              # Log additional information
              simple_error_message = I18n.t('faa.errors.invalid_application')
              detailed_error_message = simple_error_message + " Errors: #{draft_app.errors.full_messages}"
              Failure(simple_error_message: simple_error_message, detailed_error_message: detailed_error_message)
            end
          rescue StandardError => e
            # Log additional information
            simple_error_message = I18n.t('faa.errors.copy_application_error')
            detailed_error_message = simple_error_message + " Error message: #{e.message}"
            Failure(simple_error_message: simple_error_message, detailed_error_message: detailed_error_message)
          end

          def fetch_app_params(source_application)
            source_app_params = source_application.attributes.deep_symbolize_keys.slice(:family_id, :is_renewal_authorized, :years_to_renew, :is_requesting_voter_registration_application_in_mail,
                                                                                        :benchmark_product_id, :medicaid_terms, :medicaid_insurance_collection_terms, :report_change_terms,
                                                                                        :parent_living_out_of_home_terms, :attestation_terms, :submission_terms, :request_full_determination, :has_eligibility_response,
                                                                                        :transfer_requested, :account_transferred, :has_mec_check_response, :applicant_kind, :request_kind,
                                                                                        :motivation_kind, :us_state, :is_ridp_verified, :effective_date,
                                                                                        :renewal_base_year)

            source_app_params[:origin] = @origin
            source_app_params[:generation_reason] = @generation_reason
            assistance_year = @assistance_year || source_application.family.application_applicable_year || TimeKeeper.date_of_record.year
            source_app_params[:assistance_year] = assistance_year
            source_app_params[:predecessor_id] = source_application.id
            hbx_id = ::FinancialAssistance::HbxIdGenerator.generate_application_id
            source_app_params[:integrated_case_id] = hbx_id
            source_app_params.merge({ aasm_state: 'draft',
                                      hbx_id: hbx_id })
          end

          # Overrides the method to avoid persisting the new draft applicants.
          def update_claimed_as_tax_dependent_by(source_application, new_app)
            claimed_applicants = new_app.applicants.where(is_claimed_as_tax_dependent: true)
            claimed_applicants.each do |new_appl|
              new_appl.callback_update = true # avoiding callback to enroll in copy feature
              new_matching_applicant = claiming_applicant(source_application, new_appl)

              if new_matching_applicant.present?
                new_appl.claimed_as_tax_dependent_by = new_matching_applicant.id
              else
                @claiming_applicants_missing = true
              end
            end
          end

          # Overrides the method to avoid cancelling the applications without persisting the new draft application.
          def cancel_previous_applications(_draft_app)
            Success()
          end
        end
      end
    end
  end
end