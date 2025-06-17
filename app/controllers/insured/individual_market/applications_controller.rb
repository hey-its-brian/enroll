# frozen_string_literal: true

module Insured
  module IndividualMarket
    # Controller for managing applications in the individual market
    # pundit policies use QhpApplicationPolicy for applications
    class ApplicationsController < ApplicationController

      before_action :verify_qhp_application_enabled
      before_action :set_current_person
      before_action :set_family
      before_action :find_application
      before_action :check_for_non_editable_application, only: [:eligibility_criteria]
      before_action :check_for_editable_application, only: [:review, :preferences, :attestation, :submit]
      before_action :set_consumer_bookmark_url, except: [:submit]
      before_action :enable_bs4_layout

      layout "progress"

      include ::ResourceRegistryHelper

      def review
        authorize @application, :review?

        respond_to :html
      end

      def preferences
        authorize @application, :preferences?

        @applicant = @application.primary_applicant
        respond_to :html
      end

      def attestation
        authorize @application, :attestation?

        respond_to :html
      end

      def submit
        raise ActionController::UnknownFormat unless request.format.html?

        authorize @application, :submit?

        if @application.build_attestation(params[:terms_check] == "true", params[:first_name], params[:last_name], current_user)
          operation = Operations::IndividualMarket::SubmitAndDetermineApplication.new
          result = operation.call(@application)

          if result.success?
            application = result.success
            redirect_to eligibility_results_insured_individual_market_application_path(application, internal: true) and return
          else
            @application.failed_submission
            flash[:error] = result.failure
            redirect_to insured_individual_market_application_path(@application) and return
          end
        else
          flash[:error] = "Invalid attestation"
          redirect_to insured_individual_market_application_path(@application) and return
        end
      end

      def eligibility_results
        authorize @application, :eligibility_results?

        @in_application_flow = true if params.keys.include?('internal')

        respond_to :html
      end

      # this is the page used for reviewing the application
      # after it has been submitted
      def show
        authorize @application, :application_details?

        respond_to :html
      end

      def eligibility_criteria
        authorize @application, :eligibility_criteria?

        respond_to :html
      end

      # GET endpoint for copying an existing application
      # This action allows users to create a copy of an existing application
      # and redirect them to the applicants page of the new application.
      #
      # @return [Redirect] Redirects to the applicants page of the new application or back to applications list with an error message.
      def copy
        authorize @application, :copy?
        copy_result = ::Operations::IndividualMarket::Application::Copy.new.call(
          **copy_params(@application, @person, current_user)
        )

        if copy_result.success?
          new_application = copy_result.success
          redirect_to insured_individual_market_application_applicants_path(application_id: new_application.id)
        else
          flash[:error] = copy_result.failure
          redirect_to insured_sbm_applications_path
        end
      end

      private

      # Prepares parameters for copying an existing Individual Market application
      #
      # @param application [IndividualMarket::Application] The application to copy
      # @param person [Person] The person who is the primary applicant of the application
      # @param current_user [User] The current user making the request
      # @return [Hash] Parameters to pass to the Individual Market application creation
      def copy_params(application, person, logged_in_user)
        {
          application: application,
          origin: fetch_origin(person, logged_in_user),
          generation_reason: :manual
        }
      end

      def verify_qhp_application_enabled
        return render(file: 'public/404.html', status: 404) unless EnrollRegistry.feature_enabled?(:qhp_application)
        true
      end

      def find_application
        application_id = params[:application_id] || params[:id]
        @application = if current_user.try(:person).try(:agent?)
                         ::IndividualMarket::Application.find_by(id: application_id)
                       else
                         ::IndividualMarket::Application.find_by(id: application_id, family_id: get_current_person&.primary_family&.id)
                       end
      rescue Mongoid::Errors::DocumentNotFound
        authorize ::IndividualMarket::Application.new, :find_application?
      end

      def check_for_editable_application
        return if @application.current_state == :initial
        redirect_to insured_individual_market_application_path(@application)
      end

      def check_for_non_editable_application
        return if @application.is_determined?
        redirect_to review_insured_individual_market_application_path(@application)
      end

      def set_family
        @family = @person.primary_family
      end

      def application_params
        params.require(:individual_market_application).permit(
          :family_id,
          :assistance_year,
          :origin_source,
          :generation_reason
        )
      end

      def enable_bs4_layout
        @bs4 = true if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
      end
    end
  end
end
