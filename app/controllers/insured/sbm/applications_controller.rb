# frozen_string_literal: true

module Insured
  module Sbm
    # Controller for displaying FAA and QHP applications combined in the individual market
    class ApplicationsController < ApplicationController

      before_action :set_current_person
      before_action :set_family
      before_action :enable_bs4_layout
      before_action :set_consumer_bookmark_url, except: [:evidences]
      before_action :fetch_application, only: [:evidences]

      layout "progress"

      def evidences
        authorize @family, :evidences?

        @applicants = @application.applicants
        @sorted_applicants = @applicants.sort_by do |applicant|
          [applicant.cumulative_grouped_status.to_s, applicant.earliest_due_date || Float::INFINITY]
        end
        @action_items = @applicants.flat_map(&:find_action_items_and_sort)
      end

      def current_applications
        authorize @family, :current_applications?
        @applicable_year = Family.application_applicable_year
        @previous_year = @applicable_year - 1

        set_prospective_year if HbxProfile.current_hbx && !HbxProfile.current_hbx.under_open_enrollment?
      end

      def index
        authorize @family, :index?

        @copyable_application_ids = @family.fetch_copyable_application_ids
        @applicable_year = Family.application_applicable_year

        result = Operations::Sbm::Applications::QueryFilteredApplications.new.call(
          {
            family_id: @family.id,
            filter_year: params.dig(:filter, :year)
          }
        )

        if result.success?
          value = result.value!
          @applications = value[:applications]

          @filtered_applications = value[:filtered_applications]
          @recent_determined_hbx_id = value[:recent_determined_hbx_id]
          @restore_fa_info = value[:restore_fa_info]

          respond_to do |format|
            format.html
          end
        else
          respond_to do |format|
            format.json { render json: result.failure.to_h, status: 422 }
          end
        end
      end

      private

      def fetch_application
        @application = GlobalID::Locator.locate(params[:application_gid])
        return handle_not_found("Application not found") unless @application

        @family = @application.family
      end

      def handle_not_found(error_message)
        flash[:error] = error_message
        redirect_to current_applications_insured_sbm_applications_path
      end

      def set_prospective_year
        @prospective_year = @applicable_year + 1
        prospective_application = @family.application_for_year(@prospective_year)
        @prospective_application = prospective_application if prospective_application.present? && prospective_application.determined?
        @oe_start_date = HbxProfile.current_hbx.try(:benefit_sponsorship).try(:renewal_benefit_coverage_period).try(:open_enrollment_start_on)&.to_formatted_s(:long) if @prospective_application.present?
      end

      def set_family
        @family = @person.primary_family
      end

      def enable_bs4_layout
        @bs4 = true if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
      end
    end
  end
end
