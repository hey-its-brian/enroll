# frozen_string_literal: true

module Operations
  module FinancialAssistance
    module OnDetermination
      module Families
        # This class handles the create/update of a family, family members, and people
        # on the Financial Assistance (FA) application determination.
        class CreateOrUpdate
          include Dry::Monads[:do, :result]

          # The class processes the creation or update of a family and its components
          # based on a Financial Assistance Application after a determination.
          #
          # @param application [FinancialAssistance::Application] the financial assistance application
          # @return [Dry::Monads::Result] Success with family or Failure with error message
          def call(application:)
            # Step1: Find the family
            # Step2: For each applicant, find or create the person
            # Step3: For each applicant, create or update the family member
            # Step4: For each applicant, find or build the family member
            # Step5: Deactivate the old Tax Household Groups
            # Step6: Build a new Tax Household Group
            # Step7: Assign latest application GID
            # Step8: Persist the family
            # Step9: Build Family Eligibility Determination for the family
            # Step10: Update applicants with the new family member id and person hbx_id

            application, family   = yield validate_application(application)
            people_result         = yield create_or_update_people(application)
            _relationships_result = yield create_or_update_primary_relationships(people_result, application)
            family_members_result = yield build_or_update_family_members(application, family, people_result)
            _result               = yield deactivate_tax_household_groups(application, family)
            _result               = yield build_tax_household_group(application, family, family_members_result)
            family                = yield assign_latest_application_gid(family)
            family                = yield persist_family(family)
            # family_determination  = yield recreate_family_eligibility_determination(family)
            application           = yield update_application(application, family_members_result, people_result)

            Success([application, family])
          end

          private

          # Validates that the application is of the correct type and has a valid family
          #
          # @param application [Object] application to validate
          # @return [Dry::Monads::Result] Success with application and family or Failure with error message
          def validate_application(application)
            if application.is_a?(::FinancialAssistance::Application)
              if application.family.is_a?(::Family)
                Success([application, application.family])
              else
                Failure("Invalid Family for given application with hbx_id: #{application.hbx_id}")
              end
            else
              Failure('Invalid application type. Expected FinancialAssistance::Application.')
            end
          end

          # Creates or updates people for all applicants in the application
          #
          # @param application [FinancialAssistance::Application] the financial assistance application
          # @return [Dry::Monads::Result] Success with hash of applicant_id => person or Failure with results hash
          def create_or_update_people(application)
            final_result_success = true
            results = application.applicants.inject({}) do |result_hash, applicant|
              person_result = create_or_update_person_by(applicant)
              final_result_success = false if person_result.failure?
              result_hash[applicant.id] = person_result.success
              result_hash
            end

            final_result_success ? Success(results) : Failure(results)
          end

          # Creates or updates a person based on an applicant
          #
          # @param applicant [FinancialAssistance::Applicant] the applicant to create or update a person for
          # @return [Dry::Monads::Result] Success with person or Failure with error message
          def create_or_update_person_by(applicant)
            ::Operations::FinancialAssistance::OnDetermination::People::CreateOrUpdate.new.call(applicant: applicant)
          end

          # Creates or updates relationships for the primary applicant
          #
          # @param people_result [Hash] hash of applicant_id => person
          # @param application [FinancialAssistance::Application] the financial assistance application
          # @return [Dry::Monads::Result] Success with message or Failure with error message
          def create_or_update_primary_relationships(people_result, application)
            primary_applicant = application.primary_applicant
            primary_person = people_result[primary_applicant.id]

            application.relationships.where(applicant_id: primary_applicant.id).each do |rel|
              existing_rel = primary_person.person_relationships.where(relative_id: people_result[rel.relative_id].id).first

              if existing_rel.present?
                existing_rel.kind = rel.kind
              else
                primary_person.person_relationships.build(kind: rel.kind, relative_id: people_result[rel.relative_id].id)
              end
            end

            primary_person.save!

            Success('Created primary relationships')
          end

          # Builds or updates family members for all applicants
          #
          # @param application [FinancialAssistance::Application] the financial assistance application
          # @param family [Family] the family associated with the application
          # @param people_result [Hash] hash of applicant_id => person
          # @return [Dry::Monads::Result] Success with hash of applicant_id => family_member
          def build_or_update_family_members(application, family, people_result)
            # Creates or Updates family members for each applicant
            results = application.applicants.inject({}) do |result_hash, applicant|
              person = people_result[applicant.id]
              result_hash[applicant.id] = build_or_update_family_member_by(applicant, family, person)
              result_hash
            end

            # Deactivates all the family members that are not in the current application
            family.family_members.where(:id.nin => application.applicants.pluck(:family_member_id)).each do |member|
              member.is_active = false
            end

            Success(results)
          end

          # Builds or updates a family member for a specific applicant and person
          #
          # @param applicant [FinancialAssistance::Applicant] the applicant
          # @param family [Family] the family to update
          # @param person [Person] the person associated with the applicant
          # @return [FamilyMember] the built or updated family member
          def build_or_update_family_member_by(applicant, family, person)
            member = family.family_members.where(person_id: person.id).first

            if member.present?
              member.is_active = true
              member.is_primary_applicant = applicant.is_primary_applicant
              member
            else
              family.family_members.build(
                person_id: person.id,
                is_active: true,
                is_primary_applicant: applicant.is_primary_applicant
              )
            end
          end

          # Deactivates all existing tax household groups for the application's assistance year
          #
          # @param application [FinancialAssistance::Application] the financial assistance application
          # @param family [Family] the family associated with the application
          # @return [Dry::Monads::Result] Success with message
          def deactivate_tax_household_groups(application, family)
            family.tax_household_groups.by_year(application.assistance_year).each do |thhg|
              thhg.end_on = application.effective_date > thhg.start_on ? (application.effective_date - 1.day) : thhg.start_on

              thhg.tax_households.each do |thh|
                thh.effective_ending_on = application.effective_date > thh.effective_starting_on ? (application.effective_date - 1.day) : thh.effective_starting_on
              end
            end

            Success('Deactivated old Tax Household Groups')
          end

          # Builds a new tax household group with tax households based on eligibility determinations
          #
          # @param application [FinancialAssistance::Application] the financial assistance application
          # @param family [Family] the family associated with the application
          # @param family_members_result [Hash] hash of applicant_id => family_member
          # @return [Dry::Monads::Result] Success with the new tax household group
          def build_tax_household_group(application, family, family_members_result)
            thhg = family.tax_household_groups.build(
              source: 'Faa',
              application_hbx_id: application.hbx_id,
              start_on: application.effective_date,
              end_on: nil,
              assistance_year: application.assistance_year
            )

            application.eligibility_determinations.each do |elig_deter|
              thh = thhg.tax_households.build(
                eligibility_determination_hbx_id: elig_deter.hbx_assigned_id,
                yearly_expected_contribution: elig_deter.yearly_expected_contribution,
                effective_starting_on: elig_deter.effective_starting_on || application.effective_date,
                max_aptc: elig_deter.max_aptc
              )

              build_tax_household_members(thh, family_members_result, elig_deter)
            end

            Success('Successfully built tax household group.')
          end

          # Builds tax household members for a tax household based on eligibility determination
          #
          # @param thh [TaxHousehold] the tax household to add members to
          # @param family_members_result [Hash] hash of applicant_id => family_member
          # @param elig_deter [EligibilityDetermination] the eligibility determination
          # @return [Array<TaxHouseholdMember>] the built tax household members
          def build_tax_household_members(thh, family_members_result, elig_deter)
            elig_deter.applicants.each do |applicant|
              thhm = thh.tax_household_members.build(
                applicant_id: family_members_result[applicant.id].id,
                medicaid_household_size: applicant.medicaid_household_size,
                magi_medicaid_category: applicant.magi_medicaid_category,
                magi_as_percentage_of_fpl: applicant.magi_as_percentage_of_fpl,
                magi_medicaid_monthly_income_limit: applicant.magi_medicaid_monthly_income_limit,
                magi_medicaid_monthly_household_income: applicant.magi_medicaid_monthly_household_income,
                is_without_assistance: applicant.is_without_assistance,
                is_ia_eligible: applicant.is_ia_eligible,
                is_medicaid_chip_eligible: applicant.is_medicaid_chip_eligible,
                is_non_magi_medicaid_eligible: applicant.is_non_magi_medicaid_eligible,
                is_totally_ineligible: applicant.is_totally_ineligible,
                is_csr_eligible: applicant.is_csr_eligible,
                csr_percent_as_integer: applicant.csr_percent_as_integer
              )

              build_member_determinations(applicant, thhm)
            end
          end

          # Builds member determinations for a tax household member
          #
          # @param applicant [FinancialAssistance::Applicant] the applicant
          # @param thhm [TaxHouseholdMember] the tax household member
          # @return [Array<MemberDetermination>] the built member determinations
          def build_member_determinations(applicant, thhm)
            applicant.member_determinations.map do |m_determination|
              member_deter = thhm.member_determinations.build(
                kind: m_determination.kind,
                criteria_met: m_determination.criteria_met,
                determination_reasons: m_determination.determination_reasons
              )

              build_eligibility_overrides(m_determination, member_deter)
            end
          end

          # Builds eligibility overrides for a member determination
          #
          # @param m_determination [MemberDetermination] source member determination
          # @param member_deter [MemberDetermination] target member determination to add overrides to
          # @return [Array<EligibilityOverride>] the built eligibility overrides
          def build_eligibility_overrides(m_determination, member_deter)
            m_determination.eligibility_overrides.each do |override|
              member_deter.eligibility_overrides.build(
                override_rule: override.override_rule,
                override_applied: override.override_applied
              )
            end
          end

          # Assigns the latest application GID to the family
          #
          # @param family [Family] the family to assign the latest application GID to
          # @return [Dry::Monads::Result] Success with family or Failure with error message
          def assign_latest_application_gid(family)
            family.assign_latest_application_gid

            if family.latest_application_gid
              Success(family)
            else
              Rails.logger.error("QHP Application - Failed to assign latest application GID to family.")
              Failure('Failed to assign latest application GID to family.')
            end
          end

          # Persists the family to the database
          #
          # @param family [Family] the family to persist
          # @return [Dry::Monads::Result] Success with family or Failure with error message
          # @raise [StandardError] if saving the family fails
          def persist_family(family)
            if family.valid?
              family.save!
              Success(family)
            else
              Rails.logger.error("QHP Application - Family is not valid: #{family.errors.full_messages.join(', ')}")
              Failure("Family is not valid: #{family.errors.full_messages.join(', ')}")
            end
          rescue StandardError => e
            Rails.logger.error("QHP Application - Error while saving family: #{e.message}, backtrace: #{e.backtrace.join('\n')}")
            Failure("Error while saving family with error message: #{e.message}")
          end

          # def recreate_family_eligibility_determination(family)
          #   ::Operations::Eligibilities::BuildFamilyDetermination.new.call({ family: family })
          # end

          def update_application(application, family_members_result, people_result)
            application.applicants.each do |applicant|
              applicant.family_member_id = family_members_result[applicant.id].id
              applicant.person_hbx_id = people_result[applicant.id].hbx_id
            end
            application.save!

            Success(application)
          rescue StandardError => e
            Rails.logger.error("QHP Application - Error while saving application: #{e.message}, backtrace: #{e.backtrace.join('\n')}")
            Failure("Error while saving application with error message: #{e.message}")
          end
        end
      end
    end
  end
end
