# frozen_string_literal: true

module NavigationHelper
  def tell_us_about_yourself_active?
    return true if controller_name == "consumer_roles" && ['edit', 'ridp_agreement'].include?(action_name)
    return true if controller_name == "interactive_identity_verifications"
    return true if ["help_paying_coverage", "application_checklist", "application_year_selection"].include?(action_name)
    return true if controller_name == "family_members" && action_name == "index"
    return true if controller_name == "family_relationships" && action_name == "index"
  end

  def account_registration_active?
    ["search", "match"].include?(action_name)
  end

  def tell_us_about_yourself_current_step?
    return true if controller_name == "consumer_roles" && ['edit', 'ridp_agreement'].include?(action_name)
    return true if controller_name == "interactive_identity_verifications"
    return true if ["help_paying_coverage", "application_checklist", "application_year_selection"].include?(action_name)
  end

  def family_members_index_active?
    return true if controller_name == "family_members" && action_name == "index"
    return true if controller_name == "family_relationships" && action_name == "index"
  end

  def family_members_index_current_step?
    return true if controller_name == "family_relationships" && action_name == "index"
    return true if controller_name == "family_members" && action_name == "index"
  end

  def special_enrollment_period_hash
    if @change_plan.blank?
      sep_nav_options
    else
      sep_shop_for_plans_nav_options
    end
  end

  def family_info_progress_hash
    if @change_plan.present?
      qle_nav_options
    elsif @type == "employee"
      sep_nav_options
    else
      individual_nav_options
    end
  end

  def plan_shopping_progress_hash
    if @change_plan.blank? && @market_kind == "individual"
      if @enrollment_kind.blank? && is_under_open_enrollment?
        individual_nav_options
      else
        sep_nav_options
      end
    elsif @change_plan == "change_by_qle"
      qle_nav_options
    elsif @change_plan == "change_plan"
      if (@market_kind == "individual" && !is_under_open_enrollment?) || @enrollment_kind == 'sep'
        sep_shop_for_plans_nav_options
      else
        shop_for_plans_nav_options
      end
    end
  end

  def plan_shopping_nav_options(step, nav_options)
    nav = {}

    nav[:nav_options] = nav_options
    nav[:links] = false
    nav[:step] = step
    nav[:title] = l10n('insured.enroll_in_coverage')
    nav[:back_to_account_flag] = true
    nav[:show_account_button] = true
    nav[:show_help_button] = true
    nav
  end

  def new_application_nav_options(step)
    nav = {}
    nav[:nav_options] = [
      {step: 1, page_key: :help_paying_coverage, display_label: l10n('qhp_application.nav.application_type')}
    ]
    nav[:step] = step
    nav[:title] = l10n('qhp_application.nav.enroll_in_coverage')
    nav[:back_to_account_flag] = true
    nav[:show_account_button] = true
    nav[:show_help_button] = true
    nav
  end

  def sign_up_nav_options(step, show_help_button: false, dont_show_exit_button: false)
    nav = {}

    nav[:nav_options] = [
      {step: 1, page_key: :personal_info, display_label: l10n('tell_us_about_yourself')},
      {step: 2, page_key: :family_info, display_label: l10n('family_info')}
    ]
    nav[:links] = false
    nav[:step] = step
    nav[:title] = l10n('account_setup')

    nav[:show_help_button] = show_help_button ? true : (step == 2)
    nav[:show_exit_button] = true unless dont_show_exit_button
    nav[:show_previous_button] = false
    nav[:show_account_button] = false
    nav[:is_complete] = false
    nav[:back_to_account_flag] = false

    nav
  end

  def individual_nav_options
    [
      {step: 1, page_key: :personal_info, display_label: l10n('personal_information')},
      {step: 2, page_key: :verify_identity, display_label: l10n('verify_identity')},
      {step: 3, page_key: :household_info, display_label: l10n('household_info')},
      {step: 4, page_key: :choose_plan, display_label: l10n('choose_plan')},
      {step: 5, page_key: :review, display_label: l10n('confirm_selection')},
      {step: 6, page_key: :complete, display_label: l10n('complete')}
    ]
  end

  def sep_nav_options
    [
      {step: 1, page_key: :personal_info, display_label: l10n('personal_information')},
      {step: 2, page_key: :verify_identity, display_label: l10n('verify_identity')},
      {step: 3, page_key: :household_info, display_label: l10n('household_info')},
      {step: 4, page_key: :sep, display_label: l10n('insured.families.special_enrollment_period')},
      {step: 5, page_key: :choose_plan, display_label: l10n('choose_plan')},
      {step: 6, page_key: :review, display_label: l10n('confirm_selection')},
      {step: 7, page_key: :complete, display_label: l10n('complete')}
    ]
  end

  def qle_nav_options
    [
      {step: 1, page_key: :household_info, display_label: l10n('household_info')},
      {step: 2, page_key: :choose_plan, display_label: l10n('plan_selection')},
      {step: 3, page_key: :review, display_label: l10n('review')},
      {step: 4, page_key: :complete, display_label: l10n('complete')}
    ]
  end

  def sep_shop_for_plans_nav_options
    [
      {step: 1, page_key: :sep, display_label: l10n('insured.families.special_enrollment_period')},
      {step: 2, page_key: :choose_plan, display_label: l10n('plan_selection')},
      {step: 3, page_key: :review, display_label: l10n('review')},
      {step: 4, page_key: :complete, display_label: l10n('complete')}
    ]
  end

  def shop_for_plans_nav_options
    [
      {step: 1, page_key: :choose_plan, display_label: l10n('plan_selection')},
      {step: 2, page_key: :review, display_label: l10n('review')},
      {step: 3, page_key: :complete, display_label: l10n('complete')}
    ]
  end

  def verification_navigation(member, evidence)
    steps = {
      "verification" => {title: l10n('insured.families.verifications'), link: main_app.verification_insured_families_path(tab: 'verification')},
      "verification_individual" => {title: l10n('insured.families.verifications.individual'), link: verification_individual_insured_families_path(person_id: member&.person_id)}
    }

    if qhp_application_feature_enabled? && evidence.present? && evidence.evidence_group != 'ridp'
      steps["show"] = {title: l10n('insured.families.verifications.detail'), link: evidence_details_link(evidence)}
    else
      steps["verification_detail"] = {title: l10n('insured.families.verifications.detail'), link: main_app.verification_detail_insured_families_path(evidence&.detail_params)}
    end

    case action_name
    when "verification_history"
      steps["verification_history"] = {
        title: l10n('insured.families.verifications.history.verification_history'),
        link: "#"
      }
    when "history"
      steps["history"] = {
        title: l10n('insured.families.verifications.history.verification_history'),
        link: "#"
      }
    when "index"
      return { breadcrumbs: steps.values[0..2], previous_step: steps.values[1] } unless qhp_application_feature_enabled?

      steps["index"] = {
        title: l10n('insured.families.verifications.detail.document_upload_history'),
        link: "#"
      }
    end

    current_step_index = steps.keys.find_index(action_name)
    if current_step_index.present?
      { breadcrumbs: steps.values[0..current_step_index], previous_step: steps.values[current_step_index - 1] }
    else
      { breadcrumbs: steps.values[0..2], previous_step: steps.values[1] }
    end
  end

  def eligibility_navigation
    steps = {
      "show" => {title: l10n('qhp_application.show.applications'), link: "#"},
      "index" => {title: l10n('insured.sbm.applications.eligibility.history'), link: insured_sbm_applications_path}
    }

    current_step_index = steps.keys.find_index(action_name)
    { breadcrumbs: steps.values[0..current_step_index], previous_step: steps.values[current_step_index - 1] }
  end

  def individual_market_nav_options(step, application,show_account_button: true)
    nav = {}

    nav[:nav_options] = [
      {step: 1, page_key: :family_info, link: insured_individual_market_application_applicants_path(application), label: l10n('family_info')},
      {step: 2, page_key: :preferred_language, link: preferences_insured_individual_market_application_path(application), label: l10n('qhp_application.nav.preferences_label')},
      {step: 4, page_key: :review, link: "#", label: l10n('qhp_application.nav.review_label')},
      {step: 5, page_key: :attest, link: "#", label: l10n('submit')},
      {step: 6, page_key: :results, link: "#", label: l10n('qhp_application.nav.results')}
    ]
    nav[:step] = step
    nav[:title] = l10n("qhp_application.nav_header")
    nav[:links] = true

    nav[:show_help_button] = true
    nav[:show_exit_button] = true
    nav[:show_previous_button] = false
    nav[:show_account_button] = EnrollRegistry.feature_enabled?(:back_to_account_all_shop) && show_account_button
    nav[:back_to_account_flag] = true
    nav
  end
end
