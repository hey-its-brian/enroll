# frozen_string_literal: true

module VerificationHelper
  include DocumentsVerificationStatus
  include HtmlScrubberUtil
  include L10nHelper
  include ResourceRegistryHelper

  def windowed_pages(current, total)
    return (1..total).to_a if total <= 7

    pages = [1]
    pages << :gap if current > 4
    pages += ((current - 1)..(current + 1)).to_a.select { |p| p.between?(2, total - 1) }
    pages << :gap if current < total - 3
    pages << total if total > 1
    pages.uniq
  end

  def doc_status_label(doc)
    case doc.status
      when "not submitted"
        "warning"
      when "downloaded"
        "default"
      when "verified"
        "success"
      else
        "danger"
    end
  end

  def ridp_type_status(type, person)
    consumer = person.consumer_role
    case type
    when 'Identity'
      if consumer.identity_verified? || consumer.identity_rejected
        consumer.identity_validation
      elsif consumer.has_ridp_docs_for_type?(type) && !consumer.identity_rejected
        'in review'
      else
        'outstanding'
      end
    when 'Application'
      if consumer.application_verified? || consumer.application_rejected
        consumer.application_validation
      elsif consumer.has_ridp_docs_for_type?(type) && !consumer.application_rejected
        'in review'
      else
        'outstanding'
      end
    end
  end

  def display_v_type_name(type)
    case type
    when 'ME Residency'
      'Income'
    when 'Alive Status'
      'Deceased'
    else
      type
    end
  end

  def display_evidence_name(type)
    case type
    # Financial Assistance Evidences
    when :esi_evidence, :esi_mec_evidence
      l10n("faa.evidence_type_esi")
    when :local_mec_evidence
      l10n("faa.evidence_type_aces")
    when :non_esi_evidence, :non_esi_mec_evidence
      l10n("faa.evidence_type_non_esi")
    when :income_evidence
      l10n("faa.evidence_type_income")
    # Market Eligibility Verifications
    when :residency
      l10n("insured.families.verifications.types.evidence_type_residency")
    # RIDP
    when :identity
      l10n('insured.families.verifications.types.evidence_type_identity')
    # Person Level Evidences
    when :alive_status, :alive_evidence
      l10n("insured.families.verifications.types.evidence_type_alive_status")
    when :american_indian_evidence
      l10n("insured.families.verifications.types.evidences_type_american_indian")
    when :immigration_evidence
      l10n("insured.families.verifications.types.evidences_type_immigration_status")
    when :citizenship_evidence
      l10n("insured.families.verifications.types.evidences_type_citizenship")
    when :social_security_number_evidence
      l10n("insured.families.verifications.types.evidences_type_social_security_number")
    else
      type.to_s.titleize
    end
  end

  def display_verification_type_name(type)
    EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary) ? display_evidence_name(type) : display_v_type_name(type)
  end

  # @!method had_outstanding_status?(verif_type)
  # Searches for the verification type change history in the verification type, either in the type_history_elements or history_tracks.
  # If the verification type has ever been in 'outstanding' status, whether historically or currently, it will return true.
  # @param verif_type [Object] The verification type object to check.
  # @return [Boolean] Returns true if the verification type has ever been in 'outstanding' status, false otherwise.
  def had_outstanding_status?(obj)
    previous_states = fetch_previous_states(obj)
    previous_states_history = has_outstanding_history?(obj, previous_states)
    outstanding_status?(previous_states, previous_states_history, obj)
  end

  def can_display_evidence_state_market?(evidence_state)
    case evidence_state.evidence_item_key
    when Eligibilities::EvidenceState::ALIVE_STATUS
      EnrollRegistry.feature_enabled?(:alive_status) && had_outstanding_status?(evidence_state)
    when Eligibilities::EvidenceState::AMERICAN_INDIAN_STATUS
      !EnrollRegistry.feature_enabled?(:ai_an_self_attestation) || had_outstanding_status?(evidence_state)
    when Eligibilities::EvidenceState::LOCATION_RESIDENCY
      EnrollRegistry.feature_enabled?(:location_residency_verification_type)
    else
      true
    end
  end

  def can_display_evidence_state?(evidence_state, is_admin: current_user.has_hbx_staff_role?)
    return true if is_admin

    case evidence_state.evidence_group
    when 'aca_individual_market_eligibility'
      can_display_evidence_state_market?(evidence_state)
    when 'aptc_csr_credit'
      !(evidence_state.evidence_item_key == :local_mec_evidence && !FinancialAssistanceRegistry.feature_enabled?(:mec_check))
    else
      true
    end
  end

  def can_display_v_type?(verif_type)
    return true if current_user.has_hbx_staff_role?

    case verif_type&.type_name
    when VerificationType::ALIVE_STATUS
      EnrollRegistry.feature_enabled?(:alive_status) && had_outstanding_status?(verif_type)
    when VerificationType::AMERICAN_INDIAN_STATUS
      !EnrollRegistry.feature_enabled?(:ai_an_self_attestation) || had_outstanding_status?(verif_type)
    else
      true
    end
  end

  # Determines if a verification type can be displayed based on the user's role, verification type status, and feature settings.
  #
  # @param verif_type [Object, nil] The verification type object to check. Can be nil.
  # @return [Boolean] Returns true if the verification type should be displayed, false otherwise.
  def can_display_type?(obj, is_admin: current_user.has_hbx_staff_role?)
    EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary) ? can_display_evidence_state?(obj, is_admin: is_admin) : can_display_v_type?(obj)
  end

  def ridp_status_translated(type, person)
    case ridp_type_status(type, person)
    when 'in review'
      l10n("ridp_status.in_review")
    when 'valid'
      l10n("ridp_status.verified")
    when 'rejected'
      l10n('verification_type.validation_status')
    else
      l10n("ridp_status.outstanding")
    end
  end

  def verification_type_class(status)
    case status
    when 'verified', 'valid'
      'success'
    when 'review', 'negative_response_received'
      'warning'
    when 'outstanding', 'rejected'
      'danger'
    when 'curam', 'attested', 'expired', 'unverified'
      @bs4 ? 'absent' : 'default'
    when 'pending'
      'info'
    end
  end

  def ridp_type_class(type, person)
    case ridp_type_status(type, person)
    when 'valid'
      'success'
    when 'in review'
      'warning'
    when 'outstanding', 'rejected'
      'danger'
    end
  end

  def unverified?(person)
    person.consumer_role.aasm_state != "fully_verified"
  end

  def enrollment_group_unverified?(person)
    return person.primary_family.eligibility_determination&.subjects_action_needed? if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)

    is_unverified_verification_type?(person) || is_unverified_evidences?(person) || is_family_has_unverified_verifications?(person)
  end

  def is_family_has_unverified_verifications?(person)
    return false unless EnrollRegistry.feature_enabled?(:include_faa_outstanding_verifications)
    return false if person.primary_family.enrollments.enrolled_and_renewal.blank?
    ed = person.primary_family.eligibility_determination
    return false unless ed.present?
    return false unless ed.outstanding_verification_status == 'outstanding'
    !ed.outstanding_verification_earliest_due_date.nil? && ed.outstanding_verification_document_status != 'Fully Uploaded'
  end

  def is_unverified_verification_type?(person)
    person.primary_family.contingent_enrolled_active_family_members.flat_map(&:person).flat_map(&:consumer_role).flat_map(&:verification_types).select{|type| type.is_type_outstanding?}.any?
  end

  def is_unverified_evidences?(person)
    return false if person.primary_family.enrollments.enrolled_and_renewal.blank?
    application = FinancialAssistance::Application.where(family_id: person.primary_family.id).determined.order_by(:created_at => 'desc').first
    aasm_states = []
    application&.active_applicants&.each do |applicant|
      next unless applicant.is_applying_coverage
      FinancialAssistance::Applicant::EVIDENCES.each do |evidence_type|
        next if evidence_type == :income_evidence && applicant.incomes.blank?
        evidence = applicant.send(evidence_type)
        aasm_states << evidence.aasm_state if evidence.present?
      end
    end

    (Eligibilities::Evidence::OUTSTANDING_STATES & aasm_states).any?
  end

  def verification_needed?(person)
    person.primary_family.active_household.hbx_enrollments.verification_needed.any? if person.try(:primary_family).try(:active_household).try(:hbx_enrollments)
  end

  def has_enrolled_policy?(family_member)
    return true if family_member.blank?
    family_member.family.enrolled_policy(family_member).present?
  end

  def is_not_verified?(family_member, v_type)
    return true if family_member.blank?
    !(["na", "verified", "attested", "expired"].include?(v_type.validation_status))
  end

  def can_show_due_date?(person)
    ed = person.primary_family&.eligibility_determination
    ed&.outstanding_verification_earliest_due_date.present? || ed&.outstanding_verification_status&.to_s == 'outstanding'
  end

  def default_verification_due_date
    verification_document_due = EnrollRegistry[:verification_document_due_in_days].item
    TimeKeeper.date_of_record + verification_document_due.days
  end

  def documents_uploaded
    @person.primary_family.active_family_members.all? { |member| docs_uploaded_for_all_types(member) }
  end

  def member_has_uploaded_docs(member)
    true if member.person.consumer_role.try(:vlp_documents).any? { |doc| doc.identifier }
  end

  def member_has_uploaded_paper_applications(member)
    true if member.person.resident_role.try(:paper_applications).any? { |doc| doc.identifier }
  end

  def docs_uploaded_for_all_types(member)
    member.person.verification_types.all? do |type|
      member.person.consumer_role.vlp_documents.any?{ |doc| doc.identifier && doc.verification_type == type }
    end
  end

  def documents_count(family)
    family.family_members.map(&:person).flat_map(&:consumer_role).flat_map(&:vlp_documents).select{|doc| doc.identifier}.count
  end

  def get_person_v_type_status(people)
    v_type_status_list = []
    people.each do |person|
      person.verification_types.without_alive_status_type.each do |v_type|
        v_type_status_list << verification_type_status(v_type, person)
      end
    end
    v_type_status_list
  end

  def show_send_button_for_consumer?
    current_user.has_consumer_role? && hbx_enrollment_incomplete && documents_uploaded
  end

  def hbx_enrollment_incomplete
    if @person.primary_family.active_household.hbx_enrollments.verification_needed.any?
      @person.primary_family.active_household.hbx_enrollments.verification_needed.first.review_status == "incomplete"
    end
  end

  #use this method to send docs to review for family member level
  def all_docs_rejected(person)
    person.try(:consumer_role).try(:vlp_documents).select{|doc| doc.identifier}.all?{|doc| doc.status == "rejected"}
  end

  def no_enrollments
    @person.primary_family.active_household.hbx_enrollments.empty?
  end

  def enrollment_incomplete
    if @person.primary_family.active_household.hbx_enrollments.verification_needed.any?
      @person.primary_family.active_household.hbx_enrollments.verification_needed.first.review_status == "incomplete"
    end
  end

  def all_family_members_verified
    @family_members.all?{|member| member.person.consumer_role.aasm_state == "fully_verified"}
  end

  def show_doc_status(status)
    ["verified", "rejected"].include?(status)
  end

  def evidence_status(evidence)
    status = evidence.status.to_s
    text_update_feature_enabled = EnrollRegistry.feature_enabled?(:verifications_household_summary_text_update)

    case status
    when "curam"
      current_user.has_hbx_staff_role? ? l10n('insured.families.verifications.statuses.external_source') : l10n('insured.families.verifications.statuses.verified')
    when "valid"
      l10n('insured.families.verifications.statuses.verified')
    when "negative_response_received"
      text_update_feature_enabled ? l10n('not_applicable') : status.titleize
    when "review"
      text_update_feature_enabled ? l10n('insured.families.verifications.statuses.in_review') : status.titleize
    else
      status&.titleize
    end
  end

  def v_type_status(status, admin = nil)
    if status == "curam"
      admin ? "External Source".center(12) : sanitize_html("verified".capitalize.center(12).gsub(' ', '&nbsp;'))
    elsif status
      status = "verified" if status == "valid"
      status = l10n('verification_type.validation_status') if status == 'rejected'
      sanitize_html(status.titleize.center(12).gsub(' ', '&nbsp;'))
    end
  end

  def show_v_type(obj, admin = nil)
    EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary) ? evidence_status(obj) : v_type_status(obj, admin)
  end

  def show_ridp_type(ridp_type, person)
    case ridp_type_status(ridp_type, person)
    when 'in review'
      sanitize_html("&nbsp;&nbsp;&nbsp;In Review&nbsp;&nbsp;&nbsp;")
    when 'valid'
      sanitize_html("&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Verified&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;")
    when 'rejected'
      l10n('verification_type.validation_status')
    else
      sanitize_html("&nbsp;&nbsp;Outstanding&nbsp;&nbsp;")
    end
  end

  # returns vlp_documents array for verification type
  def documents_list(person, v_type)
    person.consumer_role.vlp_documents.select{|doc| doc.identifier && doc.verification_type == v_type } if person.consumer_role
  end

  # returns ridp_documents array for ridp verification type
  def ridp_documents_list(person, ridp_type)
    person.consumer_role.ridp_documents.select{|doc| doc.identifier && doc.ridp_verification_type == ridp_type } if person.consumer_role
  end

  def admin_actions(obj, f_member, display_previous_evidences: false)
    list = build_admin_actions_list(obj, f_member)
    if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
      list.delete(::VlpDocument::CALL_HUB) if display_previous_evidences
      view_history = list.delete(::VlpDocument::VIEW_HISTORY)
      {options: list, can_view_history: view_history.present?}
    else
      options_for_select(list)
    end
  end

  def display_upload_for_verification?(obj)
    if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
      (obj.grouped_status != :verified || obj.status.to_sym == :negative_response_received) && !obj.inactive
    else
      !obj.no_document_upload_required?
    end
  end

  def mod_attr(attr, val)
      attr.to_s + " => " + val.to_s
  end

  def ridp_admin_actions(ridp_type, person)
    options_for_select(build_ridp_admin_actions_list(ridp_type, person))
  end

  def build_v_type_admin_actions_list(v_type, f_member)
    if EnrollRegistry.feature_enabled?(:ai_an_self_attestation) && v_type.type_name == VerificationType::AMERICAN_INDIAN_STATUS
      [::VlpDocument::VIEW_HISTORY]
    elsif f_member.consumer_role.aasm_state == 'unverified' || VerificationType::ADMIN_CALL_HUB_VERIFICATION_TYPES.exclude?(v_type.type_name)
      ::VlpDocument::ADMIN_VERIFICATION_ACTIONS.reject{ |el| el == 'Call HUB' }
    elsif verification_type_status(v_type, f_member) == 'outstanding'
      ::VlpDocument::ADMIN_VERIFICATION_ACTIONS.reject{|el| el == "Reject" }
    else
      ::VlpDocument::ADMIN_VERIFICATION_ACTIONS
    end
  end

  def build_evidence_admin_actions_list(evidence, f_member)
    case evidence.evidence_group
    when 'aca_individual_market_eligibility'
      build_evidence_admin_actions_list_market(evidence, f_member)
    when 'aptc_csr_credit'
      build_evidence_admin_actions_list_aptc_csr(evidence)
    else
      []
    end
  end

  def build_evidence_admin_actions_list_market(evidence, f_member)
    return [::VlpDocument::VIEW_HISTORY] if evidence.inactive || (EnrollRegistry.feature_enabled?(:ai_an_self_attestation) && evidence.evidence_item_key == Eligibilities::EvidenceState::AMERICAN_INDIAN_STATUS)

    rejections = []
    rejections << ::VlpDocument::CALL_HUB if f_member.consumer_role.aasm_state == 'unverified' || Eligibilities::EvidenceState::ADMIN_CALL_HUB_VERIFICATION_TYPES.exclude?(evidence.evidence_item_key)
    rejections << ::VlpDocument::REJECT if verification_type_status(evidence, f_member) == 'outstanding'
    rejections << ::VlpDocument::EXTEND unless !EnrollRegistry.feature_enabled?(:verification_due_on_options) || (evidence.is_action_needed? && pundit_allow(HbxProfile, :can_extend_due_date?))

    ::VlpDocument::ADMIN_VERIFICATION_ACTIONS - rejections
  end

  def build_evidence_admin_actions_list_aptc_csr(evidence)
    return [] if evidence.evidence_group == 'ridp'
    return [Eligibilities::Evidence::VIEW_HISTORY] if evidence.inactive || (EnrollRegistry.feature_enabled?(:ai_an_self_attestation) && evidence.evidence_item_key == Eligibilities::EvidenceState::AMERICAN_INDIAN_STATUS)

    rejections = []
    rejections << Eligibilities::Evidence::CALL_HUB if [:alive_status, :american_indian_status].include?(evidence.evidence_item_key)
    rejections << Eligibilities::Evidence::REJECT if evidence.status == :outstanding
    rejections << Eligibilities::Evidence::EXTEND unless !EnrollRegistry.feature_enabled?(:verification_due_on_options) || (evidence.is_action_needed? && pundit_allow(HbxProfile, :can_extend_due_date?))

    Eligibilities::Evidence::ADMIN_VERIFICATION_ACTIONS - rejections
  end

  def build_admin_actions_list(obj, f_member)
    if qhp_application_feature_enabled?
      build_evidence_admin_actions_list_aptc_csr(obj)
    else
      EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary) ? build_evidence_admin_actions_list(obj, f_member) : build_v_type_admin_actions_list(obj, f_member)
    end
  end

  def evidences_v3_reject_reasons_list(evidence_key)
    case evidence_key
    when "citizenship_evidence", "immigration_evidence"
      ::VlpDocument::CITIZEN_IMMIGR_TYPE_ADD_REASONS + ::VlpDocument::ALL_TYPES_REJECT_REASONS
    else
      ::VlpDocument::ALL_TYPES_REJECT_REASONS
    end
  end

  def build_reject_reason_list(v_type)
    if EnrollRegistry.feature_enabled?(:show_new_verifications_household_summary)
      case v_type
      when :citizenship, :immigration_status
        ::VlpDocument::CITIZEN_IMMIGR_TYPE_ADD_REASONS + ::VlpDocument::ALL_TYPES_REJECT_REASONS
      else
        ::VlpDocument::ALL_TYPES_REJECT_REASONS
      end
    else
      case v_type
      when "Citizenship", "Immigration status"
        ::VlpDocument::CITIZEN_IMMIGR_TYPE_ADD_REASONS + ::VlpDocument::ALL_TYPES_REJECT_REASONS
      when "Income" #will be implemented later
        ::VlpDocument::INCOME_TYPE_ADD_REASONS + ::VlpDocument::ALL_TYPES_REJECT_REASONS
      else
        ::VlpDocument::ALL_TYPES_REJECT_REASONS
      end
    end
  end

  def build_ridp_admin_actions_list(ridp_type, person)
    if ridp_type_status(ridp_type, person) == 'outstanding'
      ::RidpDocument::ADMIN_VERIFICATION_ACTIONS.reject{|el| el == 'Reject'}
    else
      ::RidpDocument::ADMIN_VERIFICATION_ACTIONS
    end
  end

  def type_unverified?(v_type, person)
    !["verified", "valid", "attested"].include?(verification_type_status(v_type, person))
  end

  def request_response_details_formatted(person, record, v_type)
    details = request_response_details(person, record, v_type)
    return unless details.present?

    if details.is_a?(Nokogiri::XML::Document)
      return if details.errors.present?
      details&.to_xhtml(indent: 2)
    else
      JSON.pretty_generate(details)
    end
  end

  def request_response_details(person, record, v_type)
    return show_deceased_verification_response(person, record) if v_type == VerificationType::ALIVE_STATUS

    local_residency = EnrollRegistry[:enroll_app].setting(:state_residency).item
    if record.event_request_record_id
      v_type == local_residency ? show_residency_request(person, record) : show_ssa_dhs_request(person, record)
    elsif record.event_response_record_id
      v_type == local_residency ? show_residency_response(person, record) : show_ssa_dhs_response(person, record)
    end
  end

  def show_residency_request(person, record)
    raw_request = person.consumer_role.local_residency_requests.select{
        |request| request.id == BSON::ObjectId.from_string(record.event_request_record_id)
    }
    raw_request.any? ? Nokogiri::XML(raw_request.first.body) : "no request record"
  end

  def show_deceased_verification_response(person, history)
    return unless history.event_response_record_id

    event_response = person.consumer_role.alive_status_responses.select{ |response| response.id == BSON::ObjectId.from_string(history.event_response_record_id) }.first
    event_response.present? ? JSON.parse(event_response.body) : "no response record"
  end

  def show_ssa_dhs_request(person, record)
    requests = person.consumer_role.lawful_presence_determination.ssa_requests + person.consumer_role.lawful_presence_determination.vlp_requests
    raw_request = requests.select{|request| request.id == BSON::ObjectId.from_string(record.event_request_record_id)} if requests.any?
    raw_request.any? ? Nokogiri::XML(raw_request.first.body) : "no request record"
  end

  def show_residency_response(person, record)
    raw_response = person.consumer_role.local_residency_responses.select{
        |response| response.id == BSON::ObjectId.from_string(record.event_response_record_id)
    }
    raw_response.any? ? Nokogiri::XML(raw_response.first.body) : "no response record"
  end

  def show_ssa_dhs_response(person, record)
    responses = person.consumer_role.lawful_presence_determination.ssa_responses + person.consumer_role.lawful_presence_determination.vlp_responses
    raw_response = responses.select{|response| response.id == BSON::ObjectId.from_string(record.event_response_record_id)} if responses.any?
    return "no response record" unless raw_response.any?

    EnrollRegistry.feature_enabled?(:ssa_h3) ? JSON.parse(raw_response.first.body) : Nokogiri::XML(raw_response.first.body)
  rescue JSON::ParserError => e
    Rails.logger.info("JSON parse failed with error #{e}. Trying Nokogiri XML parse") unless Rails.env.test?
    Nokogiri::XML(raw_response.first.body)
  rescue Nokogiri::XML::SyntaxError => e
    Rails.logger.info("Nokogiri XML parse failed with error #{e}. Trying JSON parse") unless Rails.env.test?
    JSON.parse(raw_response.first.body)
  end

  def display_documents_tab?(family_members, person)
    family_members ||= person&.primary_family&.family_members
    any_members_with_consumer_role?(family_members)
  end

  def any_members_with_consumer_role?(family_members)
    family_members.present? && family_members.map(&:person).any?(&:has_active_consumer_role?)
  end

  def has_active_resident_members?(family_members)
    family_members.present? && family_members.map(&:person).any?(&:is_resident_role_active?)
  end

  def has_active_consumer_dependent?(person,dependent)
    person.consumer_role && person.is_consumer_role_active? && (dependent.try(:family_member).try(:person).nil? || dependent.try(:family_member).try(:person).is_consumer_role_active?)
  end

  def has_active_resident_dependent?(person,dependent)
    (dependent.try(:family_member).try(:person).nil? || dependent.try(:family_member).try(:person).is_resident_role_active?)
  end

  def ridp_type_unverified?(ridp_type, person)
    ridp_type_status(ridp_type, person) != 'valid'
  end

  private

  def fetch_previous_states(obj)
    history_elements = obj.is_a?(::Adapters::EvidenceAdapter) ? obj.history : obj&.type_history_elements
    history_elements&.pluck(:from_validation_status, :to_validation_status)&.flatten&.compact
  end

  def has_outstanding_history?(verif_type, previous_states)
    return false unless previous_states.blank?
    verif_type&.history_tracks&.any? { |ht| ht.modified["validation_status"] == 'outstanding' }
  end

  def outstanding_status?(previous_states, previous_states_history, obj)
    status = obj.is_a?(::Adapters::EvidenceAdapter) ? obj.status : obj&.validation_status
    previous_states&.include?('outstanding') || previous_states_history || status == 'outstanding'
  end

  def strong_if(is_strong:, &block)
    is_strong ? content_tag(:strong, &block) : yield
  end

  def sorted_evidence_documents(evidence)
    evidence&.documents&.most_recent_first || []
  end

  def verification_upload_query(evidence, family, display_previous_evidences: false)
    group = evidence.evidence_group.to_s
    return if group == 'ridp'

    person = evidence.person
    gid = GlobalID.parse(evidence.evidence_gid).model_id
    case group
    when 'aca_individual_market_eligibility', 'individual_market_eligibility'
      query = build_market_eligibility_query(evidence, person, gid)
    when 'aptc_csr_credit', 'aptc_csr_eligibility'
      query = build_aptc_csr_query(evidence, person, gid)
    end
    query[:params][:person_id] = person.id
    query[:params][:eligibility_kind] = evidence.evidence_group
    query[:params][:evidence_key] = evidence.evidence_item_key
    query[:params][:family] = family.id
    query[:params][:display_previous_evidences] = display_previous_evidences
    query
  end

  def build_market_eligibility_query(evidence, person, gid)
    if qhp_application_feature_enabled?
      build_qhp_application_query(evidence)
    else
      build_legacy_verification_query(person, gid)
    end
  end

  def build_aptc_csr_query(evidence, person, gid)
    if qhp_application_feature_enabled?
      build_qhp_application_query(evidence)
    else
      build_legacy_verification_query(person, gid)
    end
  end

  def evidence_document_history_link(evidence_delegator, display_previous_evidences: false)
    params = evidence_params(evidence_delegator)
    merged_params = params.merge!(display_previous_evidences: display_previous_evidences)

    eligibility_evidence_documents_path(params[:eligibility], params[:evidence], merged_params)
  end

  def evidence_details_link(evidence_delegator, display_previous_evidences: false)
    params = evidence_params(evidence_delegator)
    merged_params = params.merge!(display_previous_evidences: display_previous_evidences)

    eligibility_evidence_path(params[:eligibility], params[:evidence], merged_params)
  end

  def evidence_history_link(evidence_delegator, evidence: nil, display_previous_evidences: false)
    params = evidence_params(evidence_delegator, evidence)
    merged_params = params.merge!(display_previous_evidences: display_previous_evidences)

    history_eligibility_evidence_path(params[:eligibility], params[:evidence], merged_params)
  end

  def evidence_params(evidence_delegator, evidence = nil)
    located_evidence = evidence.present? ? evidence : evidence_delegator.locate_evidence
    eligibility = located_evidence&.eligibility
    applicant = eligibility&.eligible
    application = applicant&.application
    person = evidence_delegator.person

    {
      eligibility: eligibility,
      evidence: located_evidence,
      application_gid: application&.to_global_id&.uri&.to_s,
      applicant_id: applicant&.id,
      person_id: person.id,
      eligibility_kind: evidence_delegator.evidence_group,
      evidence_key: evidence_delegator.evidence_item_key,
      family_id: application.family.id
    }
  end

  def build_qhp_application_query(evidence)
    located_evidence = evidence.locate_evidence
    eligibility = located_evidence&.eligibility
    applicant = eligibility&.eligible
    application = applicant&.application

    {
      url: upload_eligibility_evidence_documents_path(eligibility, located_evidence),
      params: {
        application_gid: application&.to_global_id&.uri&.to_s,
        applicant_id: applicant&.id
      }
    }
  end

  def build_legacy_verification_query(person, gid)
    {
      url: insured_verification_documents_upload_path,
      params: {
        docs_owner: person.id,
        verification_type: gid
      }
    }
  end

  def build_legacy_aptc_csr_query(evidence)
    located_evidence = evidence.locate_evidence
    applicant = qhp_application_feature_enabled? ? located_evidence&.eligibility&.eligible : located_evidence&.evidenceable
    return nil unless applicant.present?

    {
      url: financial_assistance.application_applicant_verification_documents_upload_path(applicant.application, applicant),
      params: {
        applicant_id: applicant.id,
        evidence: GlobalID.parse(evidence.evidence_gid).model_id,
        evidence_kind: evidence.evidence_item_key
      }
    }
  end

  def qhp_enabled_evidence_admin_actions(evidence, display_previous_evidences)
    located_evidence = evidence.locate_evidence
    eligibility = located_evidence&.eligibility
    applicant = eligibility&.eligible
    application = applicant&.application
    evidence_key = evidence.evidence_item_key.to_s.downcase
    person = evidence.person

    {
      id: "#{applicant.id}-#{evidence_key.split.join('-')}",
      partial: {
        :partial => "eligibilities/evidences/admin_actions",
        locals: { application: application, applicant: applicant,
                  person_id: person.id,
                  eligibility_kind: evidence.evidence_group,
                  eligibility: eligibility,
                  evidence: located_evidence,
                  evidence_key: evidence_key,
                  display_previous_evidences: display_previous_evidences }
      }
    }
  end

  def verification_admin_actions(evidence, family, display_previous_evidences: false)
    return nil if evidence.evidence_group == 'ridp'
    return qhp_enabled_evidence_admin_actions(evidence, display_previous_evidences) if qhp_application_feature_enabled?

    person = evidence.person
    case evidence.evidence_group
    when 'aca_individual_market_eligibility'
      type = evidence.evidence_item_key.to_s
      gid = GlobalID.parse(evidence.evidence_gid).model_id
      {
        id: "#{person.id}-#{type.split.join('-')}",
        partial: {
          :partial => "insured/families/verification/admin_verification_actions",
          locals: {
            person: person,
            type_id: gid,
            v_type: type,
            f_member: family.find_family_member_by_person(person)
          }
        }
      }
    when 'aptc_csr_credit'
      located_evidence = evidence.locate_evidence
      applicant = qhp_application_feature_enabled? ? located_evidence&.eligibility&.eligible : located_evidence&.evidenceable
      application = applicant&.application
      evidence_kind = evidence.evidence_item_key.to_s.downcase
      {
        id: "#{applicant.id}-#{evidence_kind.split.join('-')}",
        partial: {
          :partial => "financial_assistance/applications/verifications/admin_verification_actions",
          locals: { application: application, applicant: applicant, evidence_kind: evidence_kind }
        }
      }
    end
  end

  def admin_evidence_due_on_options
    due_on = TimeKeeper.date_of_record
    static_options = EnrollRegistry[:verification_due_on_options].setting(:static_options).item
    static_options.map do |day_offset|
      incremented_day_offset = day_offset.to_i + 1 # +1 to account for DR triggers at midnight
      new_due_on = due_on + incremented_day_offset.days
      [l10n('admin.verifications.extend.due_date_options.select.static_option', day_offset: day_offset, calculated_due_on: new_due_on.strftime('%m/%d/%Y')), incremented_day_offset]
    end + [[l10n('admin.verifications.extend.due_date_options.set_manual_date'), 'manual']]
  end
end
