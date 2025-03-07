# frozen_string_literal: true

# Helper for constructing dropdown options for use in the `datatables/shared/_dropdown` partial
module DropdownHelper
  # the dropdowns used for the Applications index - these live outside of datatable
  def application_dropdowns(application)
    option_args = [
      ([l10n('faa.applications.actions.update'), edit_application_path(application), :default] if application.is_draft? || (application.imported? && current_user.has_hbx_staff_role?)),
      ([l10n('faa.applications.actions.copy'), copy_application_path(application), :default] unless do_not_allow_copy?(application, current_user)),
      ([l10n('faa.applications.actions.view_eligibility'), eligibility_results_application_path(application), :default] if application.is_determined? || application.is_terminated?),
      ([l10n('faa.applications.actions.review'), review_application_path(application), :default] if application.is_reviewable?)
    ]
    option_args = add_hbx_only_dropdowns(application, option_args)
    construct_options(option_args)
  end

  def verification_dropdowns(verification, document)
    parsed = GlobalID.parse(verification.evidence_gid)
    gid = parsed.model_id
    doc_key = document.identifier.split('#').last
    if parsed.model_class == VerificationType
      option_args = [
        [l10n('download'), "/insured/verification_documents/download/#{doc_key}", :blank_target],
        [l10n('remove'), document_path(
          document,
          :verification_type => gid,
          :doc_title => document.title&.titleize,
          :person_id => verification.eligibility_state.subject.person_id,
          :eligibility_kind => verification.eligibility_state.eligibility_item_key,
          :evidence_key => verification.evidence_item_key
        ), :delete]
      ]
    else
      application = fetch_latest_determined_application(@family.id)
      applicant = application.applicants.detect { |appl| appl.family_member_id == GlobalID::Locator.locate(verification.eligibility_state.subject.gid)&.id }
      evidence_key = verification.evidence_item_key
      option_args = [
        [l10n('download'), "/financial_assistance/applications/#{application.id}/applicants/#{applicant.id}/verification_documents/download?key=#{doc_key}&evidence_kind=#{evidence_key}", :blank_target],
        [l10n('remove'),
         financial_assistance.application_applicant_verification_documents_destroy_path(
           document,
           :applicant_id => applicant.id,
           :evidence => gid,
           :doc_key => doc_key,
           :doc_title => document.title&.titleize,
           :person_id => verification.eligibility_state.subject.person_id,
           :eligibility_kind => verification.eligibility_state.eligibility_item_key,
           :evidence_key => verification.evidence_item_key
         ), :delete]
      ]
    end

    construct_options(option_args)
  end

  # map legacy dropdowns to BS4 dropdowns
  # NOTE: should remove & refactor dropdowns from callers once BS4 is turned on
  def map_legacy_dropdown(options)
    options.each { |option| option[2] = map_legacy_dropdown_type(option[2]) }
    options.select! { |option| option[2].present? }
    construct_options(options)
  end

  private

  # dropdown type link attributes
  DEFAULT = {data: {turbolinks: false}}.freeze
  DELETE = {data: {method: 'delete'}}.freeze
  BLANK_TARGET = {target: '_blank'}.freeze
  REMOTE = {remote: true}.freeze
  REMOTE_EDIT_APTC_CSR = {class: "edit-aptc-csr-enabled", remote: true}.freeze

  def construct_options(options_args)
    options_args.compact.map { |option_args| construct_option(*option_args) }
  end

  def construct_option(title, link, option_type)
    {title: title, link: link, attributes: attribute_hash(option_type)}
  end

  # map dropdown type keys to link attributes
  def attribute_hash(option_type)
    case option_type
    when :default
      ::DropdownHelper::DEFAULT.dup
    when :delete
      ::DropdownHelper::DELETE.dup
    when :blank_target
      ::DropdownHelper::BLANK_TARGET.dup
    when :remote
      ::DropdownHelper::REMOTE.dup
    when :remote_edit_aptc_csr
      ::DropdownHelper::REMOTE_EDIT_APTC_CSR.dup
    end
  end

  def add_hbx_only_dropdowns(application, options)
    return options unless current_user.has_hbx_staff_role?
    options << ([l10n('faa.applications.actions.transfer_history'), transfer_history_application_path(application), :default] if FinancialAssistanceRegistry.feature_enabled?(:transfer_history_page))
    options << ([l10n('faa.applications.actions.full_application'), raw_application_application_path(application), :default] if current_user.has_hbx_staff_role? && application.is_reviewable?)
  end

  # map legacy dropdown types to BS4 dropdown types
  # NOTE: should remove & update dropdown types from callers once BS4 is turned on
  def map_legacy_dropdown_type(legacy_type)
    case legacy_type
    when "static"
      :default
    when "ajax"
      :remote
    when "edit_aptc_csr"
      :remote_edit_aptc_csr
    when "disabled"
      nil # disabled dropdowns are not rendered on BS4
    end
  end
end
