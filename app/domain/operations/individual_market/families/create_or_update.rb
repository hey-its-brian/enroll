# frozen_string_literal: true

module Operations
  module IndividualMarket
    module Families
      # This class handles the create/update of a family, family members, and people
      # on the Individual Market (QHP) application determination.
      class CreateOrUpdate
        include Dry::Monads[:do, :result]

        # The class processes the creation or update of a family and its components
        # based on a Individual Market Application after a determination.
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @return [Dry::Monads::Result] Success with family or Failure with error message
        def call(application:)
          application, family   = yield validate_application(application)
          people_result         = yield create_or_update_people(application)
          _relationships_result = yield create_or_update_primary_relationships(people_result, application)
          family_members_result = yield build_or_update_family_members(application, family, people_result)
          _ch_members_result    = yield build_coverage_household_members(application, family)
          _result               = yield deactivate_tax_household_groups(application, family)
          _result               = yield build_tax_household_group(application, family, family_members_result)
          family                = yield assign_latest_application_gid(family)
          family                = yield persist_family(family)
          application           = yield update_application(application, family_members_result, people_result)
          _family_determination = yield recreate_family_eligibility_determination(family)
          application           = yield update_family_timestamp(application)

          Success([application, family])
        end

        private

        # Validates that the application is of the correct type and has a valid family
        #
        # @param application [Object] application to validate
        # @return [Dry::Monads::Result] Success with application and family or Failure with error message
        def validate_application(application)
          if application.is_a?(::IndividualMarket::Application)
            family = application.family
            if family.is_a?(::Family)
              Success([application, family])
            else
              Failure("Invalid Family for given application with hbx_id: #{application.hbx_id}")
            end
          else
            Failure('Invalid application type. Expected IndividualMarket::Application.')
          end
        end

        # Creates or updates people for all applicants in the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @return [Dry::Monads::Result] Success with hash of applicant_id => person or Failure with results hash
        def create_or_update_people(application)
          final_result_success = true
          results = application.applicants.inject({}) do |result_hash, applicant|
            person_result = create_or_update_person_by(application, applicant)
            final_result_success = false if person_result.failure?
            result_hash[applicant.id] = person_result.success
            result_hash
          end

          final_result_success ? Success(results) : Failure("Error while creating or updating people: #{results.inspect}")
        end

        # Creates or updates a person based on an applicant
        #
        # @param applicant [IndividualMarket::Applicant] the applicant to create or update a person for
        # @return [Dry::Monads::Result] Success with person or Failure with error message
        def create_or_update_person_by(application, applicant)
          if application.is_renewal
            Success(applicant.person)
          else
            ::Operations::IndividualMarket::People::CreateOrUpdate.new.call(applicant: applicant)
          end
        end

        # Creates or updates relationships for the primary applicant
        #
        # @param people_result [Hash] hash of applicant_id => person
        # @param application [IndividualMarket::Application] the individual market application
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        #
        # @note This method is skipped for system-generated applications (renewals or expired_rop).
        def create_or_update_primary_relationships(people_result, application)
          return Success("Updates to Primary Relationships are not needed for System Generated Applications") if application.is_renewal

          return Failure('No primary applicant found') if application.primary_applicant.blank?
          return Success('No relationships to create') if application.relationships.blank?
          primary_applicant = application.primary_applicant
          primary_person = people_result[primary_applicant.id]
          people_result.each do |applicant_id, person|
            next if applicant_id == primary_applicant.id
            find_or_create_relationship(application, primary_person, person, applicant_id)
          end

          primary_person.save!

          Success('Created primary relationships')
        rescue StandardError => e
          Rails.logger.error("QHP Application - Error while creating primary relationships application: #{application.hbx_id}, error: #{e.message}, backtrace: #{e.backtrace.join('\n')}")
          Failure("Error while creating or updating the primary relationships with error message: #{e.message}")
        end

        # Finds or creates a relationship between the primary person and the person
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @param primary_person [Person] the primary person
        # @param person [Person] the person to create a relationship with
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        def find_or_create_relationship(application, primary_person, person, applicant_id)
          application_rel = application.relationships.where(source_id: applicant_id)&.first
          return if application_rel.blank?
          existing_rel = primary_person.person_relationships.where(relative_id: person.id)&.first
          if existing_rel.present?
            existing_rel.kind = application_rel.kind unless existing_rel.kind == application_rel.kind
          else
            primary_person.person_relationships.build(kind: application_rel.kind, relative_id: person.id)
          end
        end

        # Builds or updates family members for all applicants
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @param family [Family] the family associated with the application
        # @param people_result [Hash] hash of applicant_id => person
        # @return [Dry::Monads::Result] Success with hash of applicant_id => family_member
        def build_or_update_family_members(application, family, people_result)
          # Creates or Updates family members for each applicant
          results = application.applicants.inject({}) do |result_hash, applicant|
            person = people_result[applicant.id]
            result_hash[applicant.id] = build_or_update_family_member_by(application, applicant, family, person)
            result_hash
          end

          return Success(results) if application.is_renewal

          # Deactivates all the family members that are not associated with the applicants.
          # We should not query the applicants to get the family member IDs as the applicants are updated with the family member IDs in the `update_application` step.
          family.family_members.where(:id.nin => results.values.map(&:id)).each do |member|
            member.is_active = false
          end

          Success(results)
        end

        # Builds or updates a family member for a specific applicant and person
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @param applicant [FinancialAssistance::Applicant] the applicant
        # @param family [Family] the family to update
        # @param person [Person] the person associated with the applicant
        # @return [FamilyMember] the built or updated family member
        def build_or_update_family_member_by(application, applicant, family, person)
          return applicant.family_member if application.is_renewal

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

        # Builds coverage household members for the family based on immediate and extended family relationships
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @param family [Family] the family to build coverage household members for
        #
        # @return [Dry::Monads::Result] Success with message or Failure with error message
        #
        # @note This method is skipped for system-generated applications (renewals or expired_rop).
        def build_coverage_household_members(application, family)
          return Success("Updates to Coverage Household Members are not needed for System Generated Applications") if application.is_renewal

          immediate_ch = family.active_household.immediate_family_coverage_household
          extended_ch = family.active_household.extended_family_coverage_household
          immediate_ch.coverage_household_members.clear
          extended_ch.coverage_household_members.clear
          family.active_family_members.each do |member|
            relationship = member.primary_relationship
            if Family::IMMEDIATE_FAMILY.include?(relationship)
              immediate_ch.add_coverage_household_member(member)
            else
              extended_ch.add_coverage_household_member(member)
            end
          end
          Success('Successfully built coverage household members.')
        end

        # Deactivates all existing tax household groups for the application's assistance year
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @param family [Family] the family associated with the application
        # @return [Dry::Monads::Result] Success with message
        def deactivate_tax_household_groups(application, family)
          family.tax_household_groups.by_year(application.assistance_year).each do |thhg|
            thhg.end_on = application.effective_on > thhg.start_on ? (application.effective_on - 1.day) : thhg.start_on

            thhg.tax_households.each do |thh|
              thh.effective_ending_on = application.effective_on > thh.effective_starting_on ? (application.effective_on - 1.day) : thh.effective_starting_on
            end
          end

          Success('Deactivated old Tax Household Groups')
        end

        # Builds a new tax household group and tax household for the application
        #
        # @param application [IndividualMarket::Application] the individual market application
        # @param family [Family] the family associated with the application
        # @param family_members_result [Hash] hash of applicant_id => family_member
        #
        # @return [Dry::Monads::Result] Success with tax household group or Failure with error message
        def build_tax_household_group(application, family, family_members_result)
          thhg = family.tax_household_groups.build(
            source: 'qhp',
            application_gid: application.to_global_id.to_s,
            start_on: application.effective_on,
            end_on: nil,
            assistance_year: application.assistance_year
          )

          thh = thhg.tax_households.build(effective_starting_on: application.effective_on)

          application.applicants.each do |applicant|
            thh.tax_household_members.build(
              applicant_id: family_members_result[applicant.id].id,
              is_without_assistance: applicant.is_qhp_eligible,
              is_totally_ineligible: !applicant.is_qhp_eligible,
              is_csr_eligible: applicant.is_csr_eligible,
              csr_percent_as_integer: applicant.csr_percent
            )
          end

          Success('Successfully built tax household group and tax household.')
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

        # Recreates the family eligibility determination
        #
        # @param family [Family] the family to recreate the eligibility determination for
        # @return [Dry::Monads::Result] Success with eligibility determination or Failure with error message
        def recreate_family_eligibility_determination(family)
          ::Operations::Eligibilities::BuildFamilyDetermination.new.call({ family: family })
        end

        # Updates the application with:
        #   the new family member IDs and person HBX IDs
        #   the family_updated_at with current time
        #
        # @param application [FinancialAssistance::Application] the financial assistance application
        # @param family_members_result [Hash] hash of applicant_id => family_member
        # @param people_result [Hash] hash of applicant_id => person
        #
        # @return [Dry::Monads::Result] Success with application or Failure with error message
        #
        # @note This method is skipped for system-generated applications (renewals or expired_rop).
        def update_application(application, family_members_result, _people_result)
          # Updates to Applicants are not needed for System Generated Applications
          return Success(application) if application.is_renewal

          application.applicants.each do |applicant|
            applicant.family_member_id = family_members_result[applicant.id].id
          end
          application.save!

          Success(application)
        rescue StandardError => e
          Rails.logger.error("QHP Application - Error while saving application: #{e.message}, backtrace: #{e.backtrace.join('\n')}")
          Failure("Error while saving application with error message: #{e.message}")
        end

        # Updates the family_updated_at timestamp for the application
        # @param application [FinancialAssistance::Application] the financial assistance application
        #
        # @return [Dry::Monads::Result] Success with application or Failure with error message
        def update_family_timestamp(application)
          application.family_updated_at = Time.current
          application.save!
          Success(application)
        rescue StandardError => e
          Rails.logger.error("QHP Application - Error while updating family timestamp: #{e.message}, backtrace: #{e.backtrace.join('\n')}")
          Failure("Error while updating family timestamp with error message: #{e.message}")
        end
      end
    end
  end
end
