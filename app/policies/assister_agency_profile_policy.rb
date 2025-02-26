# frozen_string_literal: true

# policy for assister profile access
class AssisterAgencyProfilePolicy < ApplicationPolicy
  def access_to_assister_agency_profile?
    return false unless user.person
    return true if user.person.hbx_staff_role
    bap_id = record.id
    assister_role = user.person.assister_role
    return true if assister_role && assister_role.assister_agency_profile_id == bap_id && assister_role.active?
    staff_roles = user.person.assister_agency_staff_roles || []
    staff_roles.any?{|r| r.assister_agency_profile_id == bap_id && r.active?}
  end

  def update?
    return false unless user.person
    return true if user.person.hbx_staff_role
    bap_id = record.id
    assister_role = user.person.assister_role
    return true if assister_role && assister_role.assister_agency_profile_id == bap_id && assister_role.active?

    staff_roles = user.person.assister_agency_staff_roles || []
    staff_roles.any?{|r| r.assister_agency_profile_id == bap_id && r.active?}
  end

  def set_default_ga?
    return false unless user.person
    return true if user.person.hbx_staff_role
    bap_id = record.id
    assister_role = user.person.assister_role
    return true if assister_role && assister_role.assister_agency_profile_id == bap_id && assister_role.active?

    staff_roles = user.person.assister_agency_staff_roles || []
    staff_roles.any?{|r| r.assister_agency_profile_id == bap_id && r.active?}
  end
end

