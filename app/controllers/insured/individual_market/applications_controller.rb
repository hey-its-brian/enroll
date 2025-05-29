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
      before_action :set_consumer_bookmark_url, except: [:submit]
      before_action :enable_bs4_layout

      layout "progress"

      include ::ResourceRegistryHelper

      def review
        authorize @application, :review?

        respond_to :html
      end

      def voter_registration
        authorize @application, :voter_registration?

        respond_to :html
      end

      def attestation
        authorize @application, :attestation?

        respond_to :html
      end

      def submit
        raise ActionController::UnknownFormat unless request.format.html?

        authorize @application, :submit?

        # this operation has not yet been created!!!
        # result = Operations::IndividualMarket::Application::Submit.new.call(application: @application)

        # if result.success?
        #   redirect_to eligibility_results_insured_individual_market_application_path(@application)
        # else
        #   flash[:error] = result.failure
        #   redirect_to review_insured_individual_market_application_path(@application)
        # end
      end

      def eligibility_results
        authorize @application, :eligibility_results?

        respond_to :html
      end

      # this is the page used for reviewing the application
      # after it has been submitted
      def show
        authorize @application, :application_details?

        respond_to :html
      end


      private

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