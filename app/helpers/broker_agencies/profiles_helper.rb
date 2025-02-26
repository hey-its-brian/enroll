module BrokerAgencies::ProfilesHelper
  def fein_display(broker_agency_profile)
    (broker_agency_profile.organization.is_fake_fein? && !current_user.has_broker_agency_staff_role?) || (broker_agency_profile.organization.is_fake_fein? && current_user.has_hbx_staff_role?) || !broker_agency_profile.organization.is_fake_fein?
  end

  def get_commission_statements_for_year(statements, year)
    results = []
    statements.each do |statement|
      results << statement if statement.date.year == year.to_i
    end
    results
  end

  def commission_statement_formatted_date(date)
    date.strftime("%m/%d/%Y")
  end

  def commission_statement_coverage_period(date)
    date.prev_month.beginning_of_month.strftime('%b %Y').to_s
  rescue StandardError => e
    Rails.logger.warn("commission_statement_coverage_period failed due to #{e}")
    nil
  end

  def can_show_destroy_for_brokers?(broker_staff_member, total_broker_staff_count, broker_agency_profile)
    # Destroy button cannot be shown for final broker staff role
    return false if total_broker_staff_count == 1
    # Destroy button will always be shown to broker staff member if no broker role is present OR
    # Destroy button cannot be shown for broker staff member with primary broker role equal to broker agency profile primary broker
    return false if broker_agency_profile.primary_broker_role == broker_staff_member.broker_role
    broker_staff_member.broker_role.blank? || broker_staff_member.broker_role != broker_agency_profile.primary_broker_role
    #show the delete button if the broker_staff_member has a broker role but they are the primary broker on a different agency
  end

  def can_show_destroy_for_assisters?(assister_staff_member, total_assister_staff_count, assister_agency_profile)
    # Destroy button cannot be shown for final assister staff role
    return false if total_assister_staff_count == 1
    # Destroy button will always be shown to assister staff member if no assister role is present OR
    # Destroy button cannot be shown for assister staff member with primary assister role equal to assister agency profile primary assister
    return false if assister_agency_profile.primary_assister_role == assister_staff_member.assister_role
    assister_staff_member.assister_role.blank? || assister_staff_member.assister_role != assister_agency_profile.primary_assister_role
    #show the delete button if the assister_staff_member has a assister role but they are the primary assister on a different agency
  end

  def can_show_destroy_for_ga?(ga_staff_member, total_ga_staff_count)
    # Destroy button cannot be shown for final ga staff role
    return false if total_ga_staff_count == 1
    # Destroy button will always be shown to ga staff member OR
    # Destroy button cannot be shown for ga primary staff role
    ga_staff_member.general_agency_primary_staff.blank?
  end

  def disable_edit_broker_agency?(user)
    return false if user.has_hbx_staff_role?
    person = user.person
    person.broker_role.present? ? false : true
  end

  def disable_edit_assister_agency?(user)
    return true unless user
    return false if user.has_hbx_staff_role?
    person = user.person
    person.assister_role.present? ? false : true
  end

  def disable_edit_general_agency?(user)
    return false if user.has_hbx_staff_role?
    person = user.person
    person.general_agency_primary_staff.present? ? false : true
  end
end
