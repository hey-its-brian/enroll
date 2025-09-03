# frozen_string_literal: true

# Helper for constructing dropdown options for use in the `datatables/shared/_dropdown` partial
module DropdownHelper
  include ResourceRegistryHelper

  # The dropdown options for financial assistance applications.
  # This method is used to generate the dropdown options for the financial assistance applications index.
  #
  # @param application [FinancialAssistance::Application] the financial assistance application to which the dropdowns will be added
  # @param copyable_application_ids [Array] the IDs of applications that can be copied
  #
  # @return [Array] the updated dropdown options including any financial assistance specific links
  def application_dropdowns(application, copyable_application_ids, current_year = nil)
    option_args = []

    add_update_option(option_args, application)
    add_faa_copy_option(option_args, application, current_user, copyable_application_ids, current_year)
    add_eligibility_option(option_args, application)
    add_review_option(option_args, application)
    add_staff_options(option_args, application)

    construct_options(option_args)
  end

  def add_update_option(option_args, application)
    return unless application.is_draft?

    update_path = if FinancialAssistanceRegistry.feature_enabled?(:qhp_application)
                    financial_assistance.application_applicants_path(application)
                  else
                    financial_assistance.edit_application_path(application)
                  end

    option_args << [l10n('insured.sbm.applications.actions.update'), update_path, :default]
  end

  def add_eligibility_option(option_args, application)
    return unless application.is_determined? || application.is_terminated?

    option_args << [l10n('insured.sbm.applications.actions.view_eligibility'), financial_assistance.eligibility_results_application_path(application), :default]
  end

  def add_review_option(option_args, application)
    return unless application.is_reviewable? || (qhp_application_feature_enabled? && application.is_draft? && current_user.has_hbx_staff_role?)

    review_application_link = if qhp_application_feature_enabled?
                                financial_assistance.application_path(application)
                              else
                                financial_assistance.review_application_path(application)
                              end

    option_args << [l10n('insured.sbm.applications.actions.review'), review_application_link, :default]
  end

  def add_staff_options(option_args, application)
    return unless current_user.has_hbx_staff_role?

    add_transfer_history_option(option_args, application)
    add_full_application_option(option_args, application)
  end

  def add_transfer_history_option(option_args, application)
    return unless FinancialAssistanceRegistry.feature_enabled?(:transfer_history_page)

    option_args << [
      l10n('insured.sbm.applications.actions.transfer_history'),
      financial_assistance.transfer_history_application_path(application),
      :default
    ]
  end

  def add_full_application_option(option_args, application)
    return unless application.is_reviewable? && !qhp_application_feature_enabled?

    option_args << [
      l10n('insured.sbm.applications.actions.full_application'),
      financial_assistance.raw_application_application_path(application),
      :default
    ]
  end

  def add_faa_copy_option(option_args, application, current_user, copyable_application_ids, current_year)
    if qhp_application_feature_enabled?
      if show_copy?(application, copyable_application_ids, current_year, current_user)
        option_args << [l10n('insured.sbm.applications.actions.copy_to_alt_year', alt_year: current_year), financial_assistance.copy_application_path(application, assistance_year: current_year), :default]
      end
    else
      option_args << [l10n('insured.sbm.applications.actions.copy'), financial_assistance.copy_application_path(application), :default] unless do_not_allow_copy?(application, current_user, copyable_application_ids)
    end
  end

  # A method that is used only to extract common code into a single location.
  #
  # @return [Boolean]
  def show_copy?(application, copyable_application_ids, current_year, logged_in_user)
    ((logged_in_user.is_admin? && application.is_determined?) || copyable_application_ids.include?(application.id)) && current_year.present?
  end

  def add_qhp_copy_option(option_args, application, current_user, copyable_application_ids, current_year)
    return unless show_copy?(application, copyable_application_ids, current_year, current_user)

    option_args << [
      l10n('insured.sbm.applications.actions.copy_to_alt_year', alt_year: current_year),
      copy_insured_individual_market_application_path(application, assistance_year: current_year),
      :default
    ]
  end

  # The dropdown options for QHP applications.
  # This method is only applicable for QHP applications and is used to generate the dropdown options for the QHP applications index.
  #
  # @param application [IndividualMarket::Application] the QHP application to which the dropdowns will be added
  # @param copyable_application_ids [Array] the IDs of applications that can be copied
  # @param current_year [Integer] the current year for which the copied application will be created
  # @param restore_fa_info [Hash, nil] a hash containing the QHP and FAA application IDs for restoring FA information, or nil if not applicable
  #
  # @return [Array] the updated dropdown options including any QHP specific links
  def qhp_application_dropdowns(application, copyable_application_ids, current_year, restore_fa_info)
    option_args = []

    add_qhp_update_option(option_args, application)
    add_qhp_copy_option(option_args, application, current_user, copyable_application_ids, current_year)
    add_qhp_eligibility_option(option_args, application)
    add_qhp_review_option(option_args, application)
    add_restore_financial_assistance_link(option_args, application, restore_fa_info)

    construct_options(option_args)
  end

  # Method to add the 'Restore Financial Assistance' link to the dropdown options for QHP applications.
  #
  # @param option_args [Array] the array of dropdown options to which the restore link will be added
  # @param application [IndividualMarket::Application] the QHP application for which the restore
  # @param restore_fa_info [Hash, nil] a hash containing the QHP and FAA application IDs for restoring FA information, or nil if not applicable
  #
  # @return [void] modifies the option_args array in place by adding the restore link if applicable
  def add_restore_financial_assistance_link(option_args, application, restore_fa_info)
    return if restore_fa_info.nil?
    return if application.id.to_s != restore_fa_info[:qhp_app_id]

    option_args << [
      l10n('insured.sbm.applications.actions.restore_fa'),
      financial_assistance.copy_application_path(restore_fa_info[:faa_app_id], assistance_year: application.assistance_year),
      :default
    ]
  end

  def add_qhp_update_option(option_args, application)
    return unless application.is_initial?

    option_args << [
      l10n('insured.sbm.applications.actions.update'),
      insured_individual_market_application_applicants_path(application),
      :default
    ]
  end

  def add_qhp_eligibility_option(option_args, application)
    return unless application.is_determined?

    option_args << [
      l10n('insured.sbm.applications.actions.view_eligibility'),
      eligibility_results_insured_individual_market_application_path(application),
      :default
    ]

    return unless current_user.has_hbx_staff_role?

    option_args << [
      l10n('insured.sbm.applications.actions.eligibility_criteria'),
      eligibility_criteria_insured_individual_market_application_path(application),
      :default
    ]
  end

  def add_qhp_review_option(option_args, application)
    return unless application.is_reviewable? || (application.is_initial? && current_user.has_hbx_staff_role?)

    option_args << [
      l10n('insured.sbm.applications.actions.review'),
      insured_individual_market_application_path(application),
      :default
    ]
  end

  def sbm_applications_dropdowns(application, copyable_application_ids, current_year, restore_fa_info)
    if application.is_a?(::FinancialAssistance::Application)
      application_dropdowns(application, copyable_application_ids, current_year)
    else
      qhp_application_dropdowns(application, copyable_application_ids, current_year, restore_fa_info)
    end
  end

  def verification_dropdowns(verification, document)
    doc_key = document.identifier.split('#').last
    case verification.evidence_group
    when 'ridp'
      option_args = [[l10n('download'), "/insured/ridp_documents/download/#{doc_key}", :blank_target]]
    when 'aca_individual_market_eligibility'
      option_args = [[l10n('download'), "/insured/verification_documents/download/#{doc_key}", :blank_target]]
      unless verification.inactive
        option_args << [l10n('remove'), document_path(
          document,
          :verification_type => GlobalID.parse(verification.evidence_gid).model_id,
          :doc_title => document.title&.titleize,
          :person_id => verification.person.id,
          :eligibility_kind => verification.evidence_group,
          :evidence_key => verification.evidence_item_key
        ), :delete]
      end
    when 'aptc_csr_credit'
      family_member = @family.find_family_member_by_person(verification.person)
      return [] unless family_member.present?

      evidence_id = GlobalID.parse(verification.evidence_gid).model_id
      located_evidence = verification.locate_evidence
      applicant = qhp_application_feature_enabled? ? located_evidence&.eligibility&.eligible : located_evidence&.evidenceable
      application = applicant.application
      return [] unless applicant.present?

      evidence_key = verification.evidence_item_key
      option_args = [
        [l10n('download'), "/financial_assistance/applications/#{application.id}/applicants/#{applicant.id}/verification_documents/download?key=#{doc_key}&evidence_kind=#{evidence_key}", :blank_target],
        [l10n('remove'),
         financial_assistance.application_applicant_verification_documents_destroy_path(
           document,
           :applicant_id => applicant.id,
           :evidence => evidence_id,
           :doc_key => doc_key,
           :doc_title => document.title&.titleize,
           :person_id => verification.person.id,
           :eligibility_kind => verification.evidence_group,
           :evidence_kind => evidence_key
         ), :delete]
      ]
    end

    construct_options(option_args)
  end

  def qhp_enabled_verification_dropdowns(evidence_delegator, document, evidence = nil)
    doc_key = document.identifier.split('#').last

    return construct_options([[l10n('download'), "/insured/ridp_documents/download/#{doc_key}", :blank_target]]) if evidence_delegator.evidence_group == 'ridp'

    # Find all the necessary objects
    located_evidence = evidence.present? ? evidence : evidence_delegator.locate_evidence
    eligibility = located_evidence&.eligibility
    applicant = eligibility&.eligible
    application = applicant&.application
    person = evidence.present? ? applicant&.family_member&.person : evidence_delegator.person

    return [] unless applicant.present?

    # Create a context object to avoid parameter explosion
    context = {
      eligibility: eligibility,
      located_evidence: located_evidence,
      application: application,
      applicant: applicant,
      person: person,
      evidence_delegator: evidence_delegator,
      doc_key: doc_key
    }

    # Build options array
    option_args = [create_download_option(context)]
    option_args << create_remove_option(context) unless evidence_delegator.inactive

    construct_options(option_args)
  end

  def current_applications_dropdowns(application, year, draft_application, alt_year)
    if application.is_a?(::FinancialAssistance::Application)
      sbm_faa_dropdown(application, year, draft_application, alt_year)
    else
      sbm_qhp_dropdown(application, year, draft_application, alt_year)
    end
  end

  def sbm_faa_dropdown(application, year, draft_application, alt_year)
    option_args = []

    add_draft_link(option_args, draft_application, year)
    option_args << [l10n("insured.sbm.applications.actions.update_year", year: year), financial_assistance.copy_application_path(application, assistance_year: year), :default]
    option_args << [l10n("insured.sbm.applications.actions.view_eligibility"), financial_assistance.eligibility_results_application_path(application), :default] if application.is_determined? || application.is_terminated?
    option_args << [l10n("insured.sbm.applications.actions.copy_to_alt_year", alt_year: alt_year), financial_assistance.copy_application_path(application, assistance_year: alt_year), :default] if alt_year.present?

    if current_user.has_hbx_staff_role? && FinancialAssistanceRegistry.feature_enabled?(:transfer_history_page)
      option_args << (
        [
          l10n('insured.sbm.applications.actions.transfer_history'),
          financial_assistance.transfer_history_application_path(application),
          :default
        ]
      )
    end

    if application.is_reviewable? || (qhp_application_feature_enabled? && application.is_draft? && current_user.has_hbx_staff_role?)
      option_args << [l10n("insured.sbm.applications.actions.review_year", year: year), financial_assistance.review_application_path(application),
                      :default]
    end
    construct_options(option_args)
  end

  def add_draft_link(option_args, draft_application, year)
    return unless draft_application

    draft_link = draft_application.is_a?(::FinancialAssistance::Application) ? financial_assistance.application_applicants_path(draft_application) : insured_individual_market_application_applicants_path(draft_application)
    option_args << [l10n("insured.sbm.applications.actions.resume_draft_year", year: year), draft_link, :default]
  end

  def sbm_qhp_dropdown(application, year, draft_application, alt_year)
    option_args = []

    add_draft_link(option_args, draft_application, year)
    option_args << [l10n("insured.sbm.applications.actions.update_year", year: year), copy_insured_individual_market_application_path(application, assistance_year: year), :default]
    add_restore_faa_link(option_args, application, year)
    option_args << [l10n("insured.sbm.applications.actions.view_eligibility"), eligibility_results_insured_individual_market_application_path(application), :default] if application.is_determined?
    option_args << [l10n("insured.sbm.applications.actions.view_criteria"), eligibility_criteria_insured_individual_market_application_path(application), :default] if application.is_determined? && current_user.has_hbx_staff_role?
    option_args << [l10n("insured.sbm.applications.actions.copy_to_alt_year", alt_year: alt_year), copy_insured_individual_market_application_path(application, assistance_year: alt_year), :default] if alt_year.present?
    if application.is_reviewable? || (qhp_application_feature_enabled? && application.is_draft? && current_user.has_hbx_staff_role?)
      option_args << [l10n("insured.sbm.applications.actions.review_year", year: year), insured_individual_market_application_path(application),
                      :default]
    end
    construct_options(option_args)
  end

  def add_restore_faa_link(option_args, application, year)
    last_faa = application.family&.latest_determined_faa_application
    option_args << [l10n("insured.sbm.applications.actions.restore_fa"), financial_assistance.copy_application_path(last_faa, assistance_year: year), :default] if last_faa.present? && last_faa.assistance_year.in?([year - 1, year])
  end

  def current_applications_renewal_dropdowns(application, year)
    option_args = []
    if application.is_a?(::FinancialAssistance::Application)
      option_args << [l10n("insured.sbm.applications.actions.view_eligibility"), financial_assistance.eligibility_results_application_path(application), :default] if application.is_determined? || application.is_terminated?
      if application.is_reviewable? || (qhp_application_feature_enabled? && application.is_draft? && current_user.has_hbx_staff_role?)
        option_args << [l10n("insured.sbm.applications.actions.review_year", year: year), financial_assistance.review_application_path(application),
                        :default]
      end
    elsif application.is_a?(::IndividualMarket::Application)
      sbm_ivl_renewals(option_args, application, year)
    end
    construct_options(option_args)
  end

  def sbm_ivl_renewals(option_args, application, year)
    option_args << [l10n("insured.sbm.applications.actions.view_eligibility"), eligibility_results_insured_individual_market_application_path(application), :default] if application.is_determined?
    option_args << [l10n("insured.sbm.applications.actions.view_criteria"), eligibility_criteria_insured_individual_market_application_path(application), :default] if application.is_determined? && current_user.has_hbx_staff_role?
    can_be_reviewed = application.is_reviewable? || (qhp_application_feature_enabled? && application.is_draft? && current_user.has_hbx_staff_role?)
    option_args << [l10n("insured.sbm.applications.actions.review_year", year: year), insured_individual_market_application_path(application), :default] if can_be_reviewed
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

  def create_download_option(context)
    [
      l10n('download'),
      download_eligibility_evidence_documents_path(
        context[:eligibility],
        context[:located_evidence],
        application_gid: context[:application]&.to_global_id&.uri&.to_s,
        applicant_id: context[:applicant].id,
        person_id: context[:person].id,
        eligibility_kind: context[:evidence_delegator].evidence_group,
        evidence_key: context[:evidence_delegator].evidence_item_key,
        key: context[:doc_key]
      ),
      :blank_target
    ]
  end

  def create_remove_option(context)
    [
      l10n('remove'),
      eligibility_evidence_documents_path(
        context[:eligibility],
        context[:located_evidence],
        application_gid: context[:application]&.to_global_id&.uri&.to_s,
        applicant_id: context[:applicant].id,
        person_id: context[:person].id,
        eligibility_kind: context[:evidence_delegator].evidence_group,
        evidence_key: context[:evidence_delegator].evidence_item_key,
        doc_key: context[:doc_key]
      ),
      :delete
    ]
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
