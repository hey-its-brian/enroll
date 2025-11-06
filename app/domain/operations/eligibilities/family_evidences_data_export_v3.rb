# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  # export evidences
  module Eligibilities
    # Build evidences data
    class FamilyEvidencesDataExportV3
      include Dry::Monads[:do, :result]

      # @param [Hash] opts Options to update evidence due on dates
      # @option opts [Family] :family required
      # @option opts [Integer] :assistance_year required
      # @return [Dry::Monad] result
      def call(params)
        _validated = yield validate(params)
        family_data = yield construct_family_data

        Success(family_data)
      end

      private

      def ordered_column_keys
        [
          :family_hbx_id,
          :primary_hbx_id,
          :is_subscriber,
          :member_hbx_id,
          :ssn,
          :member_first_name,
          :member_last_name,
          :member_is_active,
          :health_cov_hbx_id,
          :health_cov_effective_on,
          :health_cov_applied_aptc,
          :health_cov_csr_variant,
          :health_cov_member_start,
          :health_cov_member_end,
          :other_health_covs,
          :dental_cov_hbx_id,
          :dental_cov_effective_on,
          :dental_cov_member_start,
          :dental_cov_member_end,
          :other_dental_covs,
          :citizen_kind,
          :immigrant_kind,
          :social_security_number_status,
          :social_security_number_due_date,
          :american_indian_status_status,
          :american_indian_status_due_date,
          :citizenship_status,
          :citizenship_due_date,
          :immigration_status_status,
          :immigration_status_due_date,
          :aptc_amt,
          :csr,
          :application_hbx_id,
          :application_created_at,
          :application_submitted_at,
          :applicant_applying_coverage,
          :cur_mth_earned_income_amt,
          :cur_mth_unearned_income_amt,
          :income_status,
          :income_due_date,
          :income_auto_extended,
          :income_response,
          :esi_status,
          :esi_due_date,
          :esi_response,
          :non_esi_status,
          :non_esi_due_date,
          :non_esi_response,
          :local_mec_status,
          :local_mec_due_date,
          :local_mec_response
        ]
      end

      def validate(params)
        return Failure('family missing') unless params[:family].is_a?(::Family)
        return Failure('assistance year missing') unless params[:assistance_year]
        @family = params[:family]
        @assistance_year = params[:assistance_year]
        Success(params)
      end

      def construct_family_data
        enrollments = enrollments_for_family

        results =
          @family.active_family_members.collect do |family_member|
            family_member_hash = {}

            family_member_hash.merge!(get_basic_family_data(family_member))
            family_member_hash.merge!(get_person_data(family_member.person))
            family_member_hash[:member_is_active] = family_member.is_active
            family_member_hash.merge!(get_family_member_coverage_details(enrollments, family_member))
            family_member_hash.merge!(get_citizen_status_data(family_member.person))
            family_member_hash.merge!(get_aca_individual_evidence_data(family_member))
            family_member_hash.merge!(tax_household_information(family_member, @assistance_year))
            family_member_hash.merge!(get_financial_assistance_applicant_data(family_member))

            ordered_column_keys.map { |key| family_member_hash[key] }
          end

        Success(results)
      end

      def latest_application
        qhp_app = ::IndividualMarket::Application
                  .for_determined_family(@family.id)
                  .where(assistance_year: @assistance_year)
                  .order_by(submitted_at: :desc)
                  .limit(1)
                  .first

        faa_app = ::FinancialAssistance::Application.newest_determined_by_family_and_year(@family.id, @assistance_year).first
        @latest_application ||= [qhp_app, faa_app].compact.max_by(&:submitted_at)
      end

      def enrollments_for_family
        @family
          .hbx_enrollments
          .by_year(@assistance_year)
          .enrolled_and_renewing
      end

      def get_basic_family_data(family_member)
        {
          family_hbx_id: @family.hbx_assigned_id,
          primary_hbx_id: @family.primary_person.hbx_id,
          is_subscriber: @family.primary_applicant.id == family_member.id
        }
      end

      def get_family_member_coverage_details(enrollments, family_member)
        coverage_kinds = %w[health dental]
        member_enrollments =
          enrollments.where(
            'hbx_enrollment_members.applicant_id': family_member.id
          )

        coverage_data = {}

        coverage_kinds.each do |coverage_kind|
          enrollments_by_kind =
            member_enrollments.by_coverage_kind(coverage_kind)
          current_coverage = enrollments_by_kind.last

          next unless current_coverage
          current_member = current_coverage.hbx_enrollment_members.detect { |enrollment_member|  enrollment_member.applicant_id == family_member.id }
          base_coverage_data = {
            "#{coverage_kind}_cov_hbx_id".to_sym => current_coverage.hbx_id,
            "#{coverage_kind}_cov_effective_on".to_sym => current_coverage.effective_on,
            "#{coverage_kind}_cov_member_start".to_sym => current_member.coverage_start_on,
            "#{coverage_kind}_cov_member_end".to_sym => current_member.coverage_end_on,
            "other_#{coverage_kind}_covs".to_sym => (enrollments_by_kind.pluck(:hbx_id) - [current_coverage.hbx_id]).join(',')
          }

          if coverage_kind == "health"
            csr_variant = EligibilityDetermination::CSR_KIND_TO_PLAN_VARIANT_MAP.invert[current_coverage.product.csr_variant_id]
            applied_aptc_amount = current_coverage.applied_aptc_amount.to_s

            base_coverage_data[:health_cov_applied_aptc] = applied_aptc_amount
            base_coverage_data[:health_cov_csr_variant] = csr_variant
          end

          coverage_data.merge!(base_coverage_data)
        end

        coverage_data
      end

      def get_person_data(person = nil)
        if person
          {
            member_hbx_id: person.hbx_id,
            ssn: person.ssn,
            member_first_name: person.first_name,
            member_last_name: person.last_name
          }
        else
          {}
        end
      end

      def get_citizen_status_data(person)
        key = ::ConsumerRole::US_CITIZEN_STATUS_KINDS.include?(person.citizen_status) ? :citizen_kind : :immigrant_kind
        { key => person.citizen_status }
      end

      def get_aca_individual_evidence_data(family_member)
        application = latest_application
        applicant = application&.active_applicants&.detect do |app|
          app.family_member_id == family_member.id
        end

        evidence_types = [
          'social_security_number',
          'american_indian_status',
          'citizenship',
          'immigration_status'
        ]

        evidence_data = {}

        evidence_types.each do |type_name|
          evidence = applicant&.individual_market_eligibility&.fetch_evidence(type_name)

          evidence_data["#{type_name}_status".to_sym] = evidence&.current_state
          evidence_data["#{type_name}_due_date".to_sym] = evidence&.due_on
        end

        evidence_data
      end

      def tax_household_information(family_member, year)
        if EnrollRegistry.feature_enabled?(:temporary_configuration_enable_multi_tax_household_feature)
          thhg = family_member.family.active_thhg(year)
          return {} if thhg.blank?

          thh = thhg.tax_households.where(:'tax_household_members.applicant_id' => family_member.id).first
          return {} if thh.blank?

          {
            aptc_amt: thh.max_aptc&.to_f,
            csr: thh.thhm_by(family_member)&.csr_percent_as_integer
          }
        else
          thh = family_member.family.active_household.latest_active_thh_with_year(year)
          return {} if thh.blank?

          {
            aptc_amt: thh.latest_eligibility_determination&.max_aptc&.to_f,
            csr: thh.thhm_by(family_member)&.csr_percent_as_integer
          }
        end
      end

      def get_finanacial_assistance_applicant_data(applicant)
        {
          application_hbx_id: applicant&.application&.hbx_id,
          application_created_at: applicant&.application&.created_at,
          application_submitted_at: applicant&.application&.submitted_at,
          applicant_applying_coverage: applicant&.is_applying_coverage,
          cur_mth_earned_income_amt: applicant&.current_month_earned_incomes&.sum(&:amount),
          cur_mth_unearned_income_amt: applicant&.current_month_unearned_incomes&.sum(&:amount)
        }
      end

      def get_financial_assistance_applicant_evidence_data(applicant)
        evidence_keys = %w[
          income
          esi
          non_esi
          local_mec
        ]

        evidence_data = {}

        evidence_keys.each do |evidence_key|
          evidence = applicant&.aptc_csr_eligibility&.fetch_evidence("#{evidence_key}_evidence")

          evidence_data["#{evidence_key}_status".to_sym] = evidence&.current_state
          evidence_data["#{evidence_key}_due_date".to_sym] = evidence&.due_on
          evidence_data[:income_auto_extended] = evidence ? evidence.due_date_extended_at.present? : nil if evidence_key == 'income'
          evidence_data["#{evidence_key}_response".to_sym] = evidence&.has_determination_response?
        end

        evidence_data
      end

      def get_financial_assistance_applicant_data(family_member)
        applicant = latest_application&.active_applicants&.detect { |app| app.family_member_id == family_member.id } if latest_application.is_a?(::FinancialAssistance::Application)

        fa_data = get_finanacial_assistance_applicant_data(applicant)
        evidence_data = get_financial_assistance_applicant_evidence_data(applicant)

        fa_data.merge(evidence_data)
      end
    end
  end
end
