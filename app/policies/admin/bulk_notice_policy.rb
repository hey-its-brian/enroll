# frozen_string_literal: true

#Admin::BulkNoticePolicy
module Admin
  # Policy to check if Brokers can download bulk notices
  class BulkNoticePolicy < ::ApplicationPolicy
    def initialize(user, record)
      super
      @person = user&.person
      @record = record
    end

    def can_download_document?
      return false if @person.blank?
      return true if @person.hbx_staff_role
      return true if individual_market_primary_family_member?
      return true if has_access_to_broker_agency?(@record.audience_ids)
      return true if has_access_to_assister_agency?(@record.audience_ids)

      false
    end

    def has_access_to_broker_agency?(audience_ids)
      active_broker_staff_roles = @person.active_broker_staff_roles
      broker_role = @person.broker_role

      if broker_role.present?
        audience_ids.include?(broker_role.broker_agency_profile&.organization&.id&.to_s)
      elsif active_broker_staff_roles.present?
        active_broker_staff_roles.any? do |staff_role|
          audience_ids.include?(staff_role.broker_agency_profile&.organization&.id&.to_s)
        end
      end
    end

    def has_access_to_assister_agency?(audience_ids)
      active_assister_staff_roles = @person.active_assister_staff_roles
      assister_role = @person.assister_role

      if assister_role.present?
        audience_ids.include?(assister_role.assister_agency_profile&.organization&.id&.to_s)
      elsif active_assister_staff_roles.present?
        active_assister_staff_roles.any? do |staff_role|
          audience_ids.include?(staff_role.assister_agency_profile&.organization&.id&.to_s)
        end
      end
    end
  end
end
