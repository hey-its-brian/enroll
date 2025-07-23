# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        # Fetches families with determined applications.
        class FetchLatestDeterminedFAApplicationHbxIds
          include Dry::Monads[:do, :result]

          def call(params)
            assistance_year = yield validate(params)
            application_hbx_ids = yield fetch_latest_app_for_each_family(assistance_year)
            yield fetch_applications_as_object(application_hbx_ids)
          end

          private

          def validate(params)
            return Failure("Invalid params provided") if params.empty? || params[:additional_params].nil? || params[:additional_params][:assistance_year].nil?
            assistance_year = params[:additional_params][:assistance_year]
            return Failure("Invalid assistance year provided") unless assistance_year.is_a?(Integer)

            Success(assistance_year)
          end

          def fetch_latest_app_for_each_family(assistance_year)
            result = ::FinancialAssistance::Application.collection.aggregate(
              pipeline_query(assistance_year), allow_disk_use: true
            )

            application_hbx_ids = result.collect do |hash|
              hash['application_hbx_id']
            end

            Success(application_hbx_ids)
          end

          def fetch_applications_as_object(application_hbx_ids)
            result = ::FinancialAssistance::Application.only(:_id, :hbx_id, :aasm_state, :family_id).where(hbx_id: { '$in' => application_hbx_ids })

            Success(result)
          end

          def pipeline_query(assistance_year)
            [
              { '$match' => { 'assistance_year' => assistance_year, 'aasm_state' => "determined", 'origin' => {'$ne' => 'migration'} } },
              { '$sort' => { 'submitted_at' => -1 } },
              { '$group' => { '_id' => '$family_id', 'application_hbx_id' => { '$first' => '$hbx_id' } } },
              { '$project' => { '_id' => 0, 'family_id' => '$_id', 'application_hbx_id' => 1 } }
            ]
          end
        end
      end
    end
  end
end