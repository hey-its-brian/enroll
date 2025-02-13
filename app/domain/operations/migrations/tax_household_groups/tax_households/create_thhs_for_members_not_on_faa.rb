# frozen_string_literal: true

module Operations
  module Migrations
    module TaxHouseholdGroups
      module TaxHouseholds
        # This class processes enrollments and creates tax households and thh enrs for members who are
        # added after an FAA application is determined but before the enrollment is purchased
        class CreateThhsForMembersNotOnFaa
          include Dry::Monads[:do, :result]

          # Initiates the process of updating and creating tax household enrollments
          #
          # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure]
          def call(params)
            valid_params = yield validate(params)
            enrollments = yield fetch_enrollments(valid_params)
            result = yield process_enrollments(enrollments)

            Success(result)
          end

          private

          def validate(params)
            return Failure('Pass in year') if params[:year].blank?

            Success(params)
          end

          # Fetches enrollments for the given year and coverage kind
          #
          # @return [Dry::Monads::Result::Success<Array<HbxEnrollment>>] A list of eligible enrollments
          def fetch_enrollments(valid_params)
            enrollments = HbxEnrollment.by_year(valid_params[:year].to_i)
                                       .where(coverage_kind: 'health')
                                       .where(:aasm_state.nin => %w[coverage_canceled shopping])

            Success(enrollments)
          end

          # Processes each enrollment and creates or updates tax household enrollments
          #
          # @param enrollments [Array<HbxEnrollment>] the enrollments to process
          # @return [Dry::Monads::Result::Success<String>] A success message with the path to the report
          def process_enrollments(enrollments)
            csv_file = "#{Rails.root}/create_thh_members_not_on_faa_report.csv"
            CSV.open(csv_file, 'w', force_quotes: true) do |csv|
              csv << %w[enrollment_hbx_id primary_person_hbx_id enrollment_members_without_thh_members]

              enrollments.no_timeout.each do |en|
                tax_household_group, tax_households = fetch_tax_households(en)
                next if tax_households.blank?

                missing_applicant_ids = fetch_missing_applicant_ids(en, tax_households)
                next if missing_applicant_ids.blank?

                family = en.family
                missing_person_hbx_ids = fetch_person_hbx_ids(family, missing_applicant_ids)
                existing_thh = tax_household_group.tax_households.first
                csv << [en.hbx_id, family.primary_person.hbx_id, missing_person_hbx_ids.join(', ')]

                missing_applicant_ids.each do |family_member_id|
                  family_member = family.family_members.where(id: family_member_id).first
                  uqhp_thh = tax_household_group.tax_households.create(effective_starting_on: existing_thh.effective_starting_on)
                  uqhp_thh_member = create_tax_household_member(uqhp_thh, family_member)
                  uqhp_thhe = TaxHouseholdEnrollment.find_or_create_by({ enrollment_id: en.id, tax_household_id: uqhp_thh.id })
                  enr_member = en.hbx_enrollment_members.where(applicant_id: family_member_id).first
                  update_thh_member_enr_member(family_member_id, enr_member, uqhp_thh_member, uqhp_thhe)
                end
              rescue StandardError => e
                csv << [en.hbx_id, en.family.primary_person.hbx_id, "Unable to create tax household for missing members: #{e.message}"]
              end
            end

            Success("Successfully processed all enrollments. Please check the report: #{csv_file} for more details.")
          end

          def update_thh_member_enr_member(family_member_id, enr_member, uqhp_thh_member, uqhp_thhe)
            thh_enr_member_attributes = { hbx_enrollment_member_id: enr_member.id,
                                          tax_household_member_id: uqhp_thh_member.id,
                                          age_on_effective_date: enr_member.age_on_effective_date,
                                          relationship_with_primary: enr_member.family_member.primary_relationship,
                                          date_of_birth: enr_member.person.dob }

            thhe_member = uqhp_thhe.tax_household_members_enrollment_members.find_or_create_by(family_member_id: family_member_id)
            thhe_member.update_attributes!(thh_enr_member_attributes)
          end

          def fetch_tax_households(enrollment)
            thh_enrollments = TaxHouseholdEnrollment.by_enrollment_id(enrollment.id)
            return if thh_enrollments.blank?

            thh_enrollment = thh_enrollments.first
            tax_household_group = thh_enrollment&.tax_household&.tax_household_group
            return unless tax_household_group

            tax_households = tax_household_group.tax_households
            return unless tax_households

            [tax_household_group, tax_households]
          end

          def fetch_missing_applicant_ids(enrollment, tax_households)
            thh_member_applicant_ids = tax_households.collect do |thh|
              thh.tax_household_members.pluck(:applicant_id)
            end.flatten.compact.uniq

            enr_member_applicant_ids = enrollment.hbx_enrollment_members.pluck(:applicant_id).flatten.compact.uniq

            (enr_member_applicant_ids - thh_member_applicant_ids).flatten
          end

          def fetch_person_hbx_ids(family, missing_applicant_ids)
            family.family_members.where(id: missing_applicant_ids).flat_map(&:person).flat_map(&:hbx_id)
          end

          def create_tax_household_member(uqhp_thh, family_member)
            uqhp_thh.tax_household_members.create(
              applicant_id: family_member.id,
              is_subscriber: family_member.is_primary_applicant,
              reason: 'created as part of the pivotal: 186529509',
              csr_percent_as_integer: 0,
              csr_eligibility_kind: 'csr_0',
              is_ia_eligible: false,
              is_medicaid_chip_eligible: false,
              is_uqhp_eligible: true,
              is_totally_ineligible: false,
              is_filer: false,
              is_non_magi_medicaid_eligible: false,
              is_without_assistance: true
            )
          end
        end
      end
    end
  end
end
