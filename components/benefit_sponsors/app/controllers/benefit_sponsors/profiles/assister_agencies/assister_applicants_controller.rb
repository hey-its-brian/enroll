# frozen_string_literal: true

module BenefitSponsors
  module Profiles
    module AssisterAgencies
      # AssisterApplicantsController handles the requests and actions related to assister applicants
      class AssisterApplicantsController < ::BenefitSponsors::ApplicationController
        include Exchanges::AssisterApplicantsHelper

        before_action :check_hbx_staff_role
        before_action :find_assister_applicant, only: [:edit, :update]

        def index
          @datatable = Effective::Datatables::AssisterApplicantsDataTable.new
        end

        def edit
          respond_to do |format|
            format.js
          end
        end

        def update; end

        private

        def send_secure_message_to_assister_agency(assister_role)
          hbx_admin = HbxProfile.all.first
          assister_agency = assister_role.assister_agency_profile

          subject = "Received new assister application - #{assister_role.person.full_name}"
          body = "<br><p>Following are assister details<br>Assister Name : #{assister_role.person.full_name}<br>Assister Org ID  : #{assister_role.npn}</p>"
          secure_message(hbx_admin, assister_agency, subject, body)
        end

        def find_assister_applicant
          @assister_applicant = Person.find(BSON::ObjectId.from_string(params[:id]))
        end

        def check_hbx_staff_role
          redirect_to exchanges_hbx_profiles_root_path, :flash => { :error => "You must be an HBX staff member" } unless current_user.has_hbx_staff_role?
        end
      end
    end
  end
end
