# frozen_string_literal: true

module Insured
  module Sbm
    # Controller for displaying FAA and QHP applications combined in the individual market
    class ApplicationsController < ApplicationController

      before_action :set_current_person
      before_action :set_family
      before_action :enable_bs4_layout

      layout "progress"

      def index
        authorize @family, :index?

        @copyable_application_ids = @family.fetch_copyable_faa_application_ids

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

      def set_family
        @family = @person.primary_family
      end

      def enable_bs4_layout
        @bs4 = true if EnrollRegistry.feature_enabled?(:bs4_consumer_flow)
      end
    end
  end
end
