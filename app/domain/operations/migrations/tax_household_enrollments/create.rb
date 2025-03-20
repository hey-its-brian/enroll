# frozen_string_literal: true

module Operations
  module Migrations
    module TaxHouseholdEnrollments
      # This class processes and updates TaxHouseholdEnrollment objects for APTC enrollments
      class Create
        include Dry::Monads[:do, :result]

        # Initiates the process of creating and updating TaxHouseholdEnrollments
        #
        # @param enrollment_hbx_ids [Array<String>] The HBX IDs of enrollments to process
        # @return [Dry::Monads::Result::Success, Dry::Monads::Result::Failure]
        def call(enrollment_hbx_ids:)
          enrollments = yield fetch_enrollments(enrollment_hbx_ids)
          result      = yield process_enrollments(enrollments)

          Success(result)
        end

        private

        # Fetches enrollments by HBX IDs
        #
        # @param enrollment_hbx_ids [Array<String>] The HBX IDs of enrollments to fetch
        # @return [Dry::Monads::Result::Success<Array<HbxEnrollment>>] A list of enrollments
        def fetch_enrollments(enrollment_hbx_ids)
          enrollments = HbxEnrollment.where(:hbx_id.in => enrollment_hbx_ids)
          return Failure("No enrollments found") if enrollments.empty?

          Success(enrollments)
        end

        # Processes the fetched enrollments and updates TaxHouseholdEnrollments
        #
        # @param enrollments [Array<HbxEnrollment>] The enrollments to process
        # @return [Dry::Monads::Result::Success<String>] A success message
        def process_enrollments(enrollments)
          logger = Logger.new("#{Rails.root}/update_missing_slcsp_info_for_aptc_enrs_#{Date.today.strftime('%Y_%m_%d_%H_%M')}.log")
          csv_file = "#{Rails.root}/update_missing_slcsp_info_for_aptc_enrs_report_#{Time.now.strftime('%Y_%m_%d_%H_%M')}.csv"

          CSV.open(csv_file, 'w', force_quotes: true) do |csv|
            write_csv_headers(csv)
            enrollments.each_with_index do |enrollment, index|
              create_and_update_thh_enrs(enrollment)

              enrollment.hbx_enrollment_members.each do |hbx_enr_member|
                thh_enr = find_thh_enr(enrollment, hbx_enr_member)

                csv << [
                  enrollment.family.primary_person.hbx_id,
                  enrollment.hbx_id,
                  enrollment.applied_aptc_amount.to_f,
                  enrollment.effective_on,
                  enrollment.aasm_state,
                  thh_member_enr_member_exists?(thh_enr, hbx_enr_member),
                  member_determination_type(enrollment, hbx_enr_member),
                  thh_enr&.id&.to_s || 'N/A',
                  thh_enr&.household_benchmark_ehb_premium,
                  thh_enr&.health_product_hios_id,
                  thh_enr&.dental_product_hios_id,
                  thh_enr&.household_health_benchmark_ehb_premium,
                  thh_enr&.household_dental_benchmark_ehb_premium,
                  thh_enr&.applied_aptc,
                  thh_enr&.available_max_aptc,
                  thh_enr&.group_ehb_premium
                ]
              end

              logger.info "Processed #{index + 1} enrollments" if (index + 1) % 10 == 0
            rescue StandardError => e
              logger.error "Failed to process enrollment with HBX ID: #{enrollment.hbx_id}, Error: #{e.message}"
            end
          end

          Success("Created Tax household enrollments successfully. Report generated at #{csv_file}")
        end

        def write_csv_headers(csv)
          csv << [
            'Primary Member HBX ID',
            'Enrollment HBX ID',
            'Enrollment Applied APTC amount',
            'Enrollment Effective Date',
            'Enrollment Aasm State',
            'THEnrMember exists?',
            'Tax Household Member determination',
            'THEnr identifier',
            'THEnr household_benchmark_ehb_premium',
            'THEnr health_product_hios_id',
            'THEnr dental_product_hios_id',
            'THEnr household_health_benchmark_ehb_premium',
            'THEnr household_dental_benchmark_ehb_premium',
            'THEnr applied_aptc',
            'THEnr available_max_aptc',
            'THEnr group_ehb_premium'
          ]
        end

        def find_eligible_thhg(enrollment)
          thhgs = enrollment.family.tax_household_groups.by_year(enrollment.effective_on.year).order_by(created_at: :desc)
          thhgs.detect do |thhg|
            thh_members = thhg.tax_households.flat_map(&:tax_household_members)
            enrolled_applicant_ids = enrolled_family_member_ids(enrollment)
            enrolled_applicant_ids - thh_members.map(&:applicant_id) &&
              thh_members.select { |thhm| thhm.is_ia_eligible && enrolled_applicant_ids.include?(thhm.applicant_id) }.present?
          end
        end

        def create_tax_household_enrs_with_members(enrollment)
          eligible_thhg = find_eligible_thhg(enrollment)
          build_taxhousehold_enrollments(enrollment, eligible_thhg)
        end

        def build_taxhousehold_enrollments(hbx_enrollment, tax_household_group)
          eligible_thhs = tax_household_group.tax_households.where(
            :tax_household_members => {
              :$elemMatch => {
                :applicant_id.in => enrolled_family_member_ids(hbx_enrollment),
                is_ia_eligible: true
              }
            }
          )

          eligible_thhs.each do |tax_household|
            th_enrollment = TaxHouseholdEnrollment.find_or_create_by(enrollment_id: hbx_enrollment.id, tax_household_id: tax_household.id)
            hbx_enrollment_members = hbx_enrollment.hbx_enrollment_members
            aptc_thh_members = tax_household.tax_household_members.where(is_ia_eligible: true)

            (aptc_thh_members.map(&:applicant_id).map(&:to_s) & enrolled_family_member_ids(hbx_enrollment).map(&:to_s)).each do |family_member_id|
              hbx_enrollment_member = hbx_enrollment_members.where(applicant_id: family_member_id).first
              tax_household_member_id = aptc_thh_members.where(applicant_id: family_member_id).first&.id

              th_member_enr_member = th_enrollment.tax_household_members_enrollment_members.find_or_create_by(
                family_member_id: family_member_id
              )

              th_member_enr_member.update!(
                hbx_enrollment_member_id: hbx_enrollment_member&.id,
                tax_household_member_id: tax_household_member_id,
                age_on_effective_date: hbx_enrollment_member&.age_on_effective_date,
                relationship_with_primary: hbx_enrollment_member&.primary_relationship,
                date_of_birth: hbx_enrollment_member&.person&.dob
              )
            end
          end
        end

        # Creates and updates TaxHouseholdEnrollments for a given enrollment
        def create_and_update_thh_enrs(enrollment)
          create_tax_household_enrs_with_members(enrollment)
          update_slcsp_info(enrollment)
          update_tax_household_enrollments(enrollment)
        end

        # Finds TaxHouseholdEnrollment for a given enrollment and member
        def find_thh_enr(enrollment, hbx_enr_member)
          TaxHouseholdEnrollment.where(
            enrollment_id: enrollment.id,
            :'tax_household_members_enrollment_members.hbx_enrollment_member_id' => hbx_enr_member.id
          ).first
        end

        # Checks if a TaxHouseholdMemberEnrollmentMember exists for a given member
        def thh_member_enr_member_exists?(thh_enr, hbx_enr_member)
          if thh_enr&.tax_household&.tax_household_members&.where(applicant_id: hbx_enr_member.applicant_id)&.first.present?
            'Exists'
          else
            'Missing'
          end
        end

        # Determines the type of a TaxHouseholdMember for a given member
        def member_determination_type(enrollment, hbx_enr_member)
          thhm = thh_enrs(enrollment).first.tax_household.tax_household_group.tax_households.where(
            :'tax_household_members.applicant_id' => hbx_enr_member.applicant_id
          ).first&.tax_household_members&.where(applicant_id: hbx_enr_member.applicant_id)&.first

          if thhm.blank?
            'Tax Household Member Missing'
          elsif thhm.is_ia_eligible
            'is_ia_eligible'
          elsif thhm.is_without_assistance
            'is_without_assistance'
          elsif thhm.is_medicaid_chip_eligible
            'is_medicaid_chip_eligible'
          elsif thhm.is_totally_ineligible
            'is_totally_ineligible'
          else
            'N/A'
          end
        end

        def thh_enrs(enrollment)
          TaxHouseholdEnrollment.where(enrollment_id: enrollment.id)
        end

        def aptc_thh_enrs(enrollment)
          thh_enrs(enrollment).select do |thh_enr|
            thh_enr.tax_household.tax_household_members.where(is_ia_eligible: true, :applicant_id.in => enrolled_family_member_ids(enrollment)).present?
          end
        end

        def enrolled_family_member_ids(enrollment)
          enrollment.hbx_enrollment_members.pluck(:applicant_id)
        end

        # Updates the SLCSP information for a given enrollment
        def update_slcsp_info(enrollment)
          valid_thh_enrs = aptc_thh_enrs(enrollment)
          households_hash = valid_thh_enrs.inject([]) do |result, thh_enr|
            tax_household = thh_enr.tax_household
            members_hash = (tax_household.aptc_members.map(&:applicant_id) & enrolled_family_member_ids(enrollment)).inject([]) do |member_result, member_id|
              family_member = FamilyMember.find(member_id)

              member_result << {
                family_member_id: member_id,
                coverage_start_on: enrollment.hbx_enrollment_members.where(applicant_id: member_id).first&.coverage_start_on,
                relationship_with_primary: family_member.primary_relationship
              }

              member_result
            end

            next result if members_hash.blank?

            result << {
              household_id: tax_household.id.to_s,
              members: members_hash
            }
            result
          end

          return if households_hash.blank?

          payload = {
            family_id: enrollment.family.id,
            effective_date: enrollment.effective_on,
            households: households_hash
          }

          result = ::Operations::BenchmarkProducts::IdentifySlcspWithPediatricDentalCosts.new.call(payload)
          return result if result.failure?

          benchmark_premiums = result.value!

          valid_thh_enrs.each do |thh_enr|
            persist_tax_household_enrollment(benchmark_premiums, enrollment, thh_enr)
          end
        end

        def update_tax_household_enrollments(enrollment)
          aptc_tax_household_enrollments = enrollment.send(:aptc_tax_household_enrollments)
          thh_enr_premiums = enrollment.send(:thh_enr_group_ehb_premium_of_aptc_members, aptc_tax_household_enrollments)

          if aptc_tax_household_enrollments.count == 1
            aptc_tax_household_enrollments.each do |thh_enr|
              thh_enr.update_attributes!(
                {
                  applied_aptc: enrollment.applied_aptc_amount,
                  group_ehb_premium: thh_enr_premiums[thh_enr][:group_ehb_premium]
                }
              )
            end
          elsif enrollment.applied_aptc_amount == enrollment.total_ehb_premium.to_money
            aptc_tax_household_enrollments.each do |thh_enr|
              thh_enr.update_attributes!(
                {
                  applied_aptc: thh_enr_premiums[thh_enr][:group_ehb_premium],
                  group_ehb_premium: thh_enr_premiums[thh_enr][:group_ehb_premium]
                }
              )
            end
          else
            aptc_tax_household_enrollments.each do |thh_enr|
              thh_enr.update_attributes!(
                {
                  applied_aptc: thh_enr.available_max_aptc * enrollment.elected_aptc_pct,
                  group_ehb_premium: thh_enr_premiums[thh_enr][:group_ehb_premium]
                }
              )
            end
          end
        end

        # Updates and persists TaxHouseholdEnrollment details
        def persist_tax_household_enrollment(benchmark_premiums, enrollment, thh_enr)
          tax_household = thh_enr.tax_household
          household_info = benchmark_premiums.households.find { |household| household.household_id == tax_household.id.to_s }
          hh_benchmark_premium = (household_info&.household_benchmark_ehb_premium || 0.0)

          thh_enr.update!(
            household_benchmark_ehb_premium: hh_benchmark_premium,
            health_product_hios_id: household_info&.health_product_hios_id,
            dental_product_hios_id: household_info&.dental_product_hios_id,
            household_health_benchmark_ehb_premium: household_info&.household_health_benchmark_ehb_premium,
            household_dental_benchmark_ehb_premium: household_info&.household_dental_benchmark_ehb_premium,
            available_max_aptc: hh_benchmark_premium
          )

          persist_tax_household_members_enrollment_members(enrollment, tax_household, thh_enr, household_info)
        end

        # Persists details for TaxHouseholdMembers linked to EnrollmentMembers
        def persist_tax_household_members_enrollment_members(enrollment, tax_household, th_enrollment, household_info)
          return if household_info.blank?

          tax_household_group = find_tax_household_group(enrollment, tax_household)
          return unless tax_household_group

          hbx_enrollment_members = enrollment.hbx_enrollment_members
          tax_household_members = tax_household_group.tax_households.first.tax_household_members

          matching_family_member_ids(tax_household, hbx_enrollment_members).each do |family_member_id|
            persist_member_enrollment(
              family_member_id,
              hbx_enrollment_members,
              tax_household_members,
              th_enrollment,
              household_info
            )
          end
        end

        def find_tax_household_group(enrollment, tax_household)
          th_id = BSON::ObjectId.from_string(tax_household.id.to_s)
          enrollment.family.tax_household_groups.order_by(created_at: :desc)
                    .where(:"tax_households._id" => th_id).first
        end

        def matching_family_member_ids(tax_household, hbx_enrollment_members)
          tax_household.aptc_members.map(&:applicant_id).map(&:to_s) &
            hbx_enrollment_members.map(&:applicant_id).map(&:to_s)
        end

        def persist_member_enrollment(family_member_id, hbx_enrollment_members, tax_household_members, th_enrollment, household_info)
          member_info = find_member_info(household_info, family_member_id)
          return if member_info.blank?

          hbx_enrollment_member_id = hbx_enrollment_members.where(applicant_id: family_member_id).first&.id
          tax_household_member_id = tax_household_members.where(applicant_id: family_member_id).first&.id

          th_member_enr_member = th_enrollment.tax_household_members_enrollment_members.find_or_create_by(
            family_member_id: family_member_id
          )

          update_member_enrollment(th_member_enr_member, hbx_enrollment_member_id, tax_household_member_id, member_info)
        end

        def find_member_info(household_info, family_member_id)
          household_info.members.find { |member| member[:family_member_id].to_s == family_member_id.to_s }
        end

        def update_member_enrollment(th_member_enr_member, hbx_enrollment_member_id, tax_household_member_id, member_info)
          th_member_enr_member.update!(
            hbx_enrollment_member_id: hbx_enrollment_member_id&.to_s,
            tax_household_member_id: tax_household_member_id&.to_s,
            age_on_effective_date: member_info.age_on_effective_date,
            relationship_with_primary: member_info.relationship_with_primary,
            date_of_birth: member_info.date_of_birth
          )
        end
      end
    end
  end
end
