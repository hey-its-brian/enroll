# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Eligibilities
    # Build grant based on the type passed in arguments
    class BuildGrant
      include Dry::Monads[:do, :result]
      include ::ResourceRegistryHelper

      def call(params)
        values = yield validate(params)
        grants = yield build_grants(values)

        Success(grants)
      end

      private

      def validate(params)
        errors = []
        errors << 'family or family_member is missing' unless params[:family] || params[:family_member]
        errors << 'grant_type is missing' unless params[:type]

        errors.empty? ? Success(params) : Failure(errors)
      end

      def latest_tax_household_group_per_year(values)
        values[:family].tax_household_groups.active.group_by(&:assistance_year).collect do |_year, th_group|
          th_group.max_by(&:created_at)
        end.compact
      end

      # Constructs APTC grants parameters for a given tax household group.
      # It retrieves the APTC members from the tax household group and constructs grant parameters.
      #
      # @param th_group [TaxHouseholdGroup] the tax household group
      # @return [Array<Hash>] an array of hashes containing grant parameters for each APTC member
      def constructs_aptc_grants_params(th_group)
        th_group.tax_households.collect do |tax_household|
          next if tax_household.aptc_members.blank?

          {
            :title => 'aptc_grant',
            :key => 'AdvancePremiumAdjustmentGrant',
            :value => tax_household.yearly_expected_contribution&.to_s,
            :start_on => th_group.start_on,
            :end_on => th_group.end_on,
            :assistance_year => th_group.assistance_year,
            :member_ids => tax_household.aptc_members.map{|member| member.applicant_id.to_s},
            :tax_household_group_id => th_group.id.to_s,
            :tax_household_id => tax_household.id.to_s
          }
        end.compact
      end

      # This method is used to get the csr members for the family member in the tax household group.
      # It checks if the qhp application feature is enabled and returns the csr members accordingly.
      #
      # @param th_group [TaxHouseholdGroup] the tax household group
      # @param family_member [FamilyMember] the family member
      # @return [Array] the csr members for the family member in the tax household group
      def csr_grant_members(th_group, family_member)
        if qhp_application_feature_enabled?
          th_group.tax_households.where("tax_household_members.applicant_id" => family_member.id).flat_map(&:csr_members)
        else
          th_group.tax_households.where("tax_household_members.applicant_id" => family_member.id).flat_map(&:aptc_members)
        end
      end

      # Constructs CSR grants parameters for a given tax household group and family member.
      # It retrieves the CSR members from the tax household group with matching family member ID and constructs grant parameters.
      #
      # @param th_group [TaxHouseholdGroup] the tax household group
      # @param family_member [FamilyMember] the family member
      # @return [Array<Hash>] an array of hashes containing grant parameters for each CSR member
      def constructs_csr_grants_params(th_group, family_member)
        members = csr_grant_members(th_group, family_member).collect do |tax_household_member|
          next unless tax_household_member.applicant_id == family_member.id
          tax_household_member
        end.compact

        members.collect do |member|
          {
            :title => 'csr_grant',
            :key => 'CsrAdjustmentGrant',
            :value => member.csr_percent_as_integer.to_s,
            :start_on => th_group.start_on,
            :end_on => th_group.end_on,
            :assistance_year => th_group.assistance_year,
            :member_ids => [family_member.id.to_s]
          }
        end.compact
      end

      # Constructs MagiMedicaid grants parameters for a given tax household group and family member.
      # It retrieves the MagiMedicaid members from the tax household group with matching family member ID and constructs grant parameters.
      #
      # @param th_group [TaxHouseholdGroup] the tax household group
      # @param family_member [FamilyMember] the family member
      # @return [Array<Hash>] an array of hashes containing grant parameters for each MagiMedicaid member
      def constructs_magi_medicaid_grants_params(th_group, family_member)
        thh = th_group.tax_households.where('tax_household_members.applicant_id' => family_member.id).first
        return [] unless thh

        thhm = thh.magi_medicaid_members.where(applicant_id: family_member.id).first
        return [] unless thhm

        [
          {
            title: 'magi_medicaid_grant',
            key: 'MagiMedicaidGrant',
            value: thhm.is_medicaid_chip_eligible.to_s,
            start_on: th_group.start_on,
            end_on: th_group.end_on,
            assistance_year: th_group.assistance_year,
            member_ids: [family_member.id.to_s]
          }
        ]
      end

      # Constructs QHP grants parameters for a given tax household group and family member.
      # It retrieves the QHP members from the tax household group with matching family member ID and constructs grant parameters.
      #
      # @param th_group [TaxHouseholdGroup] the tax household group
      # @param family_member [FamilyMember] the family member
      # @return [Array<Hash>] an array of hashes containing grant parameters for each QHP member
      def constructs_qhp_grants_params(th_group, family_member)
        thh = th_group.tax_households.where('tax_household_members.applicant_id' => family_member.id).first
        return [] unless thh

        thhm = thh.qhp_members.where(applicant_id: family_member.id).first
        return [] unless thhm

        [
          {
            title: 'qhp_grant',
            key: 'QhpGrant',
            value: thhm.is_without_assistance.to_s,
            start_on: th_group.start_on,
            end_on: th_group.end_on,
            assistance_year: th_group.assistance_year,
            member_ids: [family_member.id.to_s]
          }
        ]
      end

      # Builds grants based on the type specified in the values hash.
      # It retrieves the latest tax household groups per year and creates grants accordingly.
      #
      # @param values [Hash] a hash containing the family, family_member, and type
      # @return [Array<Hash>] an array of hashes containing grant parameters
      def build_grants(values)
        groups = latest_tax_household_group_per_year(values)

        grants = groups.collect do |th_group|
          case values[:type]
          when 'AdvancePremiumAdjustmentGrant'
            constructs_aptc_grants_params(th_group)
          when 'CsrAdjustmentGrant'
            constructs_csr_grants_params(th_group, values[:family_member])
          when 'MagiMedicaidGrant'
            constructs_magi_medicaid_grants_params(th_group, values[:family_member])
          when 'QhpGrant'
            constructs_qhp_grants_params(th_group, values[:family_member])
          else
            []
          end
        end.flatten.compact

        Success(grants)
      end
    end
  end
end
