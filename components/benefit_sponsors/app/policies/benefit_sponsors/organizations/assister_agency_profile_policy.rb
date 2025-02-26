# frozen_string_literal: true

module BenefitSponsors
  module Organizations
    # NOTE: to pass the GHAs, this file pulls from components/benefit_sponsors/spec/dummy/app/policies/application_policy.rb
    # but in a production env will inherit from the main app ApplicationPolicy
    class AssisterAgencyProfilePolicy < ::ApplicationPolicy

      # NOTE: this method is only used by the AssisterAgencyProfileStaffRolesController
      def new?
        access_to_assister_agency_profile?
      end

      def redirect_signup?
        access_to_assister_agency_profile?
      end

      def index?
        return true if individual_market_admin?
        return true if shop_market_admin?

        false
      end

      def show?
        access_to_assister_agency_profile?
      end

      def access_to_assister_agency_profile?
        return true if individual_market_admin?
        return true if shop_market_admin?
        return true if has_matching_assister_role?
        return true if has_matching_assister_agency_staff_role?

        false
      end

      def set_default_ga?
        access_to_assister_agency_profile?
      end

      def staff_index?
        return true if individual_market_admin?
        return true if shop_market_admin?
        return true if account_holder&.has_consumer_role?

        false
      end

      def family_index?
        access_to_assister_agency_profile?
      end

      def family_datatable?
        access_to_assister_agency_profile?
      end

      def commission_statements?
        access_to_assister_agency_profile?
      end

      def show_commission_statement?
        access_to_assister_agency_profile?
      end

      def download_commission_statement?
        access_to_assister_agency_profile?
      end

      def general_agency_index?
        access_to_assister_agency_profile?
      end

      def messages?
        access_to_assister_agency_profile?
      end

      def inbox?
        access_to_assister_agency_profile?
      end

      protected

      def has_matching_assister_agency_staff_role?
        staff_roles = account_holder_person&.assister_agency_staff_roles || []
        staff_roles&.any? do |sr|
          sr.active? &&
            (
              sr.assister_agency_profile_id == record.id ||
                sr.benefit_sponsors_assister_agency_profile_id == record.id
            )
        end
      end

      def has_matching_assister_role?
        assister_role = account_holder_person&.assister_role
        return false unless assister_role

        assister_role&.benefit_sponsors_assister_agency_profile_id == record.id && assister_role&.active?
      end
    end
  end
end
