# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  module Sbm
    module Applications
      # Query FAA and QHP applications and associated data for a specified family.
      #
      # Also includes caching and performance improvements to reduce query
      # times.
      class QueryFilteredApplications
        include Dry::Monads[:do, :result]

        def call(params)
          validated_params = yield validate_params(params)
          query_filtered_records(validated_params)
        end

        def query_filtered_records(params)
          family_id = params[:family_id]
          filter_year = params[:filter_year]

          # Fetch applications
          qhp_applications = fetch_qhp_applications(family_id, filter_year)
          faa_applications = fetch_faa_applications(family_id, filter_year)
          all_applications = qhp_applications + faa_applications

          # Sort applications by creation date
          filtered_applications = all_applications.sort_by(&:created_at).reverse

          # Find the most recent determined application's HBX ID
          recent_determined_hbx_id = find_recent_determined_hbx_id(all_applications)

          Success(
            {
              applications: all_applications,
              filtered_applications: filtered_applications,
              recent_determined_hbx_id: recent_determined_hbx_id
            }
          )
        end

        def validate_params(params)
          validation_result = ::Validators::Sbm::FilteredApplicationIndexRequestContract.new.call(params)
          validation_result.success? ? Success(validation_result.to_h) : Failure(validation_result.errors)
        end

        def fetch_qhp_applications(family_id, filter_year)
          query = ::IndividualMarket::Application.where(family_id: family_id)
                                                 .only(:hbx_id, :assistance_year, :created_at, :submitted_at, :current_state)

          query = query.where(assistance_year: filter_year) if filter_year.present?
          query.to_a
        end

        def fetch_faa_applications(family_id, filter_year)
          query = ::FinancialAssistance::Application.where(family_id: family_id)
                                                    .only(:hbx_id, :assistance_year, :created_at, :submitted_at, :aasm_state)

          query = query.where(assistance_year: filter_year) if filter_year.present?
          query.to_a
        end

        def find_recent_determined_hbx_id(applications)
          determined_apps = find_determined_apps(applications)
          return nil if determined_apps.empty?

          most_recent_year = determined_apps.map(&:assistance_year).max
          recent_app = determined_apps
                       .select { |app| app.assistance_year == most_recent_year }
                       .max_by(&:submitted_at)

          recent_app&.hbx_id
        end

        def find_determined_apps(applications)
          applications.select do |app|
            case app
            when ::FinancialAssistance::Application
              app.aasm_state.to_s == "determined"
            when ::IndividualMarket::Application
              app.current_state.to_s == "determined"
            end
          end
        end
      end
    end
  end
end
