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

      def create_aptc_grants(th_group)
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
      def eligible_members(th_group, family_member)
        if qhp_application_feature_enabled?
          th_group.tax_households.where("tax_household_members.applicant_id" => family_member.id).flat_map(&:csr_members)
        else
          th_group.tax_households.where("tax_household_members.applicant_id" => family_member.id).flat_map(&:aptc_members)
        end
      end

      def create_csr_grants(th_group, family_member)
        members = eligible_members(th_group, family_member).collect do |tax_household_member|
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

      def build_grants(values)
        groups = latest_tax_household_group_per_year(values)

        grants = groups.collect do |th_group|
          case values[:type]
          when 'AdvancePremiumAdjustmentGrant'
            create_aptc_grants(th_group)
          when 'CsrAdjustmentGrant'
            create_csr_grants(th_group, values[:family_member])
          else
            []
          end
        end.flatten.compact

        Success(grants)
      end
    end
  end
end
