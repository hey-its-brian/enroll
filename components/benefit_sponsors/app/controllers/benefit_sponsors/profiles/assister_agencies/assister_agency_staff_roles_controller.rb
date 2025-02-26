# frozen_string_literal: true

module BenefitSponsors
  module Profiles
    module AssisterAgencies
      # controller that manages adding, approving and removing of staff agency roles to a assister agency profile
      class AssisterAgencyStaffRolesController < ::BenefitSponsors::ApplicationController
        before_action :find_assister_agency_profile, only: [:new]
        before_action :enable_bs4_layout, only: [:new, :create] if EnrollRegistry.feature_enabled?(:bs4_broker_flow)

        def new
          # this endpoint is used for two scenarios
          # 1.) to render the form for assisters/agents creating new assister agency staff roles for their assister agencies
          # 2.) to render a different form in the view for benefit_sponsors/profiles/registrations/new for non-users sending in applications to be staff for existing assister agencies
          # authorization is only enforced here for the first scenario
          authorize @assister_agency_profile if request.format.js?

          @staff = BenefitSponsors::Organizations::OrganizationForms::StaffRoleForm.for_new

          respond_to do |format|
            # the js template is for the first scenario metioned above^
            format.js  { render 'new' } if params[:profile_id]

            # the html template is for the second scenario metioned above^
            if params[:profile_type] && @bs4
              format.html { render partial: 'new_staff_applicant' }
            elsif params[:profile_type]
              format.html { render 'new', layout: false }
            end
          end
        end

        # The endpoint is used to create applications to existing assister agencies and can be sent by anyone
        # This endpoint is unauthorized by design
        def create
          @staff = BenefitSponsors::Organizations::OrganizationForms::StaffRoleForm.for_create(assister_staff_params)

          begin
            @status,@result = @staff.save
            unless @staff.is_assister_registration_page
              flash[:notice] = "Staff member #{assister_staff_params[:first_name]} #{assister_staff_params[:last_name]} has been added." if @status
              flash[:warning] = "Role was not added because #{@result}" unless @status
            end
          rescue StandardError => e
            flash[:error] = "Role was not added because #{e.message}"
          end
          respond_to do |format|
            format.html  { redirect_to profiles_assister_agencies_assister_agency_profile_path(id: params[:profile_id]) }
            format.js
          end
        end

        def approve
          @staff = BenefitSponsors::Organizations::OrganizationForms::StaffRoleForm.for_approve(assister_staff_params)
          authorize @staff
          begin
            @status, @result = @staff.approve
            if @status
              person = Person.find(@staff.person_id)
              flash[:notice] = "Staff member #{person.first_name} #{person.last_name} has been approved."
            else
              flash[:error] = "Role was not approved because #{@result}"
            end
          rescue StandardError => e
            flash[:error] = "Role was not approved because #{e.message}"
          end
          redirect_to profiles_assister_agencies_assister_agency_profile_path(id: params[:profile_id])
        end

        def destroy
          @staff = BenefitSponsors::Organizations::OrganizationForms::StaffRoleForm.for_destroy(assister_staff_params)
          authorize @staff
          begin
            @status, @result = @staff.destroy
            if @status
              flash[:notice] = "Role removed successfully"
            else
              flash[:error] = "Role was not removed because #{@result}"
            end
          rescue StandardError => e
            flash[:error] = "Role was not removed because #{e.message}"
          end
          redirect_to profiles_assister_agencies_assister_agency_profile_path(id: params[:profile_id])
        end

        # This endpoint should remain unauthorized: it is used by BenefitSponsors::Profiles::RegistrationsController to search for Assister Agencies
        # By design, users do not have to be logged in to use this endpoint
        def search_assister_agency
          @staff = BenefitSponsors::Organizations::OrganizationForms::StaffRoleForm.for_assister_agency_search(assister_staff_params)
          @assister_agency_profiles = @staff.assister_agency_search
        end

        private

        def find_assister_agency_profile
          return unless params[:profile_id]
          profile_id = BSON::ObjectId(params[:profile_id])

          organizations = BenefitSponsors::Organizations::Organization.where(:"profiles._id" => profile_id)
          @assister_agency_profile = organizations&.first&.assister_agency_profile
        end

        def assister_staff_params
          params[:staff].presence || params[:staff] = {}
          params[:staff].merge!({profile_id: params["staff"]["profile_id"] || params["profile_id"] || params["id"], person_id: params["person_id"], profile_type: params[:profile_type] || "assister_agency_staff",
                                 filter_criteria: params.permit(:q), is_assister_registration_page: params[:assister_registration_page] || params["staff"]["is_assister_registration_page"]})
          params[:staff].permit!
        end

        def enable_bs4_layout
          @bs4 = true
        end
      end
    end
  end
end
