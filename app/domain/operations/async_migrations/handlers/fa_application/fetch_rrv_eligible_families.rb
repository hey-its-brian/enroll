# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module FAApplication
        # This operation fetches all Financial Assistance applications for the given aasm_state
        # This operation can be retriggered multiple times, and it will only return applications that do not have v3 eligibilities.
        # Operations::AsyncMigrations::Handlers::FAApplication::FetchRRVEligibleFamilies.new.call({additional_params: {assistance_year: 2026}})
        class FetchRRVEligibleFamilies
          include Dry::Monads[:do, :result]

          def call(params)
            assistance_year = yield validate(params)
            yield fetch_rrv_eligible_family_ids(assistance_year)
          end

          private

          def validate(params)
            return Failure("Invalid params provided") if params.empty? || params[:additional_params].nil? || params[:additional_params][:assistance_year].nil?
            assistance_year = params[:additional_params][:assistance_year]
            return Failure("Invalid assistance year provided") unless assistance_year.is_a?(Integer)

            Success(assistance_year)
          end

          def fetch_rrv_eligible_family_ids(assistance_year)
            family_ids = ::FinancialAssistance::Application.where(
              aasm_state: "determined",
              assistance_year: assistance_year,
              :"applicants.is_ia_eligible" => true
            ).exists(predecessor_id: true).distinct(:family_id)

            Success(family_ids)
          end
        end
      end
    end
  end
end
