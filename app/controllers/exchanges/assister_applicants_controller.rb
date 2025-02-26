# frozen_string_literal: true

module Exchanges
  # AssisterApplicantsController handles the requests and actions related to assister applicants
  class AssisterApplicantsController < ApplicationController
    layout :resolve_layout

    before_action :check_hbx_staff_role
    before_action :find_assister_applicant, only: [:edit, :update]
    before_action :set_cache_headers, only: [:index, :edit]
    before_action :enable_bs4_layout if EnrollRegistry.feature_enabled?(:bs4_admin_flow)

    def index
      @people = Person.assister_role_having_agency

      status_params = params.permit(:status)
      @status = AssisterRole::ASSISTER_ROLE_STATUS_TYPES.include?(status_params[:status]) ? status_params[:status] : 'applicant'
      @people = @people.send("assister_role_#{@status}") if @people.respond_to?("assister_role_#{@status}")
      @page_alphabets = page_alphabets(@people, "last_name")

      if params[:page].present?
        page_no = cur_page_no(@page_alphabets.first)
        @assister_applicants = @people.where("last_name" => /^#{Regexp.escape(page_no)}/i)
      else
        @assister_applicants = sort_by_latest_transition_time(@people)&.limit(20)&.entries
      end

      respond_to do |format|
        format.html { render "shared/assisters/applicants" }
        format.js
      end
    end

    def edit
      respond_to do |format|
        format.html { render "shared/assisters/applicant.html.erb" }
      end
    end

    def update
      assister_role = @assister_applicant.assister_role
      update_assister_reason(assister_role)

      case action_type
      when 'deny'
        deny_assister(assister_role)
      when 'update'
        update_assister_role(assister_role)
      when 'decertify'
        decertify_assister(assister_role)
      when 'recertify'
        recertify_assister(assister_role)
      when 'extend'
        extend_assister(assister_role)
      when 'pending'
        mark_assister_as_pending(assister_role)
      when 'sendemail'
        send_assister_invite(assister_role)
      else
        approve_assister(assister_role)
      end

      redirect_to "/exchanges/hbx_profiles"
    end

    private

    def update_assister_reason(assister_role)
      return unless params.dig(:person, :assister_role_attributes, :reason).present?

      assister_role.update(reason: params.require(:person).require(:assister_role_attributes).permit(:reason)[:reason])
    end

    def action_type
      params.keys.find { |key| %w[deny update decertify recertify extend pending sendemail].include?(key) }
    end

    def deny_assister(assister_role)
      assister_role.deny!
      flash[:notice] = "Assister applicant denied."
    end

    def decertify_assister(assister_role)
      assister_role.decertify!
      flash[:notice] = "Assister applicant decertified."
    end

    def update_assister_role(assister_role)
      if assister_role.update!(assister_role_update_params)
        flash[:notice] = "Assister applicant successfully updated."
      else
        flash[:error] = "Unable to update assister applicant."
      end
    end

    def recertify_assister(assister_role)
      assister_role.recertify!
      flash[:notice] = "Assister applicant is now approved."
    end

    def extend_assister(assister_role)
      assister_role.extend_application!
      flash[:notice] = "Assister applicant is now extended."
    end

    def mark_assister_as_pending(assister_role)
      assister_carrier_appointments
      assister_role.update(params.require(:person).require(:assister_role_attributes).permit(:training, :license, carrier_appointments: {}).except(:id))
      assister_role.pending!
      flash[:notice] = "Assister applicant is now pending."
    end

    def send_assister_invite(assister_role)
      assister_role.send_invitation
      flash[:notice] = "Assister invite email has been resent."
    end

    def approve_assister(assister_role)
      assister_carrier_appointments
      assister_role.update(params.require(:person).require(:assister_role_attributes).permit(:training, :license, carrier_appointments: {}).except(:id))
      assister_role.approve!
      assister_role.reload

      create_and_approve_staff_role_and_approve_agency(assister_role)
      send_secure_message_to_assister_agency(assister_role) if assister_role.agency_pending? && assister_role.assister_agency_profile

      flash[:notice] = "Assister applicant approved successfully."
    end

    # @method create_and_approve_staff_role_and_approve_agency(assister_role)
    # Creates a Assister Agency Staff Role (BASR) for a person with a consumer role and approves both the agency and the staff role.
    #
    # This method checks if the assister role is a primary assister.
    # If it is, it creates a BASR for the person associated with the assister role.
    # It then approves the assister agency profile associated with the assister role, if it is in a state where it may be approved.
    # Finally, it accepts the newly created BASR, if it is in a state where it may be accepted.
    #
    # @param [AssisterRole] assister_role The assister role for which to create a BASR and approve the agency and staff role.
    #
    # @return [void] This method does not return a value. It modifies the state of the assister role, the assister agency profile, and the BASR.
    #
    # @example Create a BASR and approve both the agency and the staff role for a primary assister role
    #   create_and_approve_staff_role_and_approve_agency(assister_role)
    def create_and_approve_staff_role_and_approve_agency(assister_role)
      Operations::EnsureAssisterStaffRoleForPrimaryAssister.new(:application_approved).call(assister_role)
    end

    def assister_role_update_params
      # Only assign if nil
      params[:person][:assister_role_attributes][:carrier_appointments] ||= {}
      params[:person][:assister_role_attributes].permit(:license, :training, :carrier_appointments => {})
    end

    def assister_carrier_appointments
      all_carrier_appointments = EnrollRegistry[:brokers].setting(:carrier_appointments).item.stringify_keys
      assister_carrier_appointments_enabled = Settings.aca.broker_carrier_appointments_enabled
      if assister_carrier_appointments_enabled
        params[:person][:assister_role_attributes][:carrier_appointments] = all_carrier_appointments.each{ |key,_str| all_carrier_appointments[key] = "true" }
      else
        # Fix this
        permitted_params = params.require(:person).require(:assister_role_attributes).permit(:carrier_appointments => {}).to_h
        all_carrier_appointments.merge!(permitted_params[:carrier_appointments]) if permitted_params[:carrier_appointments]
        params[:person][:assister_role_attributes][:carrier_appointments] = all_carrier_appointments
      end
    end

    def send_secure_message_to_assister_agency(assister_role)
      hbx_admin = HbxProfile.all.first
      assister_agency = assister_role.assister_agency_profile

      subject = "Received new assister application - #{assister_role.person.full_name}"
      body = "<br><p>Following are assister details<br>Assister Name : #{assister_role.person.full_name}<br>Assister Org Id  : #{assister_role.assister_org_id}</p>"
      secure_message(hbx_admin, assister_agency, subject, body)
    end

    def find_assister_applicant
      @assister_applicant = Person.find(BSON::ObjectId.from_string(params[:id]))
    end

    def check_hbx_staff_role
      redirect_to exchanges_hbx_profiles_root_path, :flash => { :error => "You must be an HBX staff member" } unless current_user.has_hbx_staff_role?
    end

    def enable_bs4_layout
      @bs4 = true
    end

    def resolve_layout
      EnrollRegistry.feature_enabled?(:bs4_admin_flow) ? "progress" : "single_column"
    end

    def sort_by_latest_transition_time(assister_applicants)
      assister_applicants.order_by("assister_role.workflow_state_transitions.created_at": :desc)
    end
  end
end
