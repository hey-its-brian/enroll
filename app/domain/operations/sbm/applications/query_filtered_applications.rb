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

        private

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
              recent_determined_hbx_id: recent_determined_hbx_id,
              restore_fa_info: fetch_restore_fa_info(faa_applications, qhp_applications)
            }
          )
        end

        # Fetches the QHP application ID for showing the Financial Assistance Restore button
        #
        # @param faa_applications [Array<FinancialAssistance::Application>] list of FA applications
        # @param qhp_applications [Array<IndividualMarket::Application>] list of QHP applications
        #
        # @return [Hash, nil] returns a hash with QHP and FAA application IDs if both are found, otherwise nil
        def fetch_restore_fa_info(faa_applications, qhp_applications)
          return nil unless open_enrollment_active?
          return nil unless has_renewal_qhp_applications?(qhp_applications)

          assistance_year = current_assistance_year
          renewal_qhp_app = find_renewal_qhp_application(qhp_applications, assistance_year)
          renewal_faa_app = find_eligible_faa_application(faa_applications, assistance_year)

          return unless renewal_qhp_app.present? && renewal_faa_app.present?

          { qhp_app_id: renewal_qhp_app.id.to_s, faa_app_id: renewal_faa_app.id.to_s }
        end

        # Returns the current HBX profile
        #
        # @return [HbxProfile] the current HBX profile
        def hbx_profile
          return @hbx_profile if defined?(@hbx_profile)

          @hbx_profile = HbxProfile.current_hbx
        end

        # Checks if the current open enrollment period is active
        #
        # @return [Boolean] true if the open enrollment period is active, false otherwise
        def open_enrollment_active?
          return false unless hbx_profile

          bcp = hbx_profile.current_oe_bcp
          bcp.present?
        end

        # Checks if the given QHP applications include any renewal applications
        #
        # @param qhp_applications [Array<IndividualMarket::Application>] list of QHP applications
        #
        # @return [Boolean] true if there are renewal applications, false otherwise
        def has_renewal_qhp_applications?(qhp_applications)
          qhp_applications.any?(&:is_renewal)
        end

        # Returns the current assistance year
        #
        # @return [Integer] the current assistance year
        def current_assistance_year
          hbx_profile.current_oe_bcp.start_on.year.next
        end

        # Finds renewal QHP application for the given assistance year
        #
        # @param qhp_applications [Array<IndividualMarket::Application>] list of QHP applications
        # @param assistance_year [Integer] the assistance year to filter by
        #
        # @return [IndividualMarket::Application, nil] the found renewal application or nil
        def find_renewal_qhp_application(qhp_applications, assistance_year)
          qhp_applications.detect { |app| app.is_renewal && app.assistance_year == assistance_year }
        end

        # Finds eligible FAA application for the given assistance year
        #
        # @param faa_applications [Array<FinancialAssistance::Application>] list of FAA applications
        # @param assistance_year [Integer] the assistance year to filter by
        #
        # @return [FinancialAssistance::Application, nil] the found eligible application or nil
        def find_eligible_faa_application(faa_applications, assistance_year)
          eligible_states = %w[applicants_update_required income_verification_extension_required]
          faa_applications.detect do |app|
            eligible_states.include?(app.aasm_state.to_s) && app.assistance_year == assistance_year
          end
        end

        def validate_params(params)
          validation_result = ::Validators::Sbm::FilteredApplicationIndexRequestContract.new.call(params)
          validation_result.success? ? Success(validation_result.to_h) : Failure(validation_result.errors)
        end

        def fetch_qhp_applications(family_id, filter_year)
          query = ::IndividualMarket::Application.where(family_id: family_id).only(
            :hbx_id, :assistance_year, :created_at, :submitted_at, :current_state, :is_renewal
          )

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
