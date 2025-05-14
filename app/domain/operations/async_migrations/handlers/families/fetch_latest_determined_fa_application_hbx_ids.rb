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
            data_hash = yield fetch_eligible_families(assistance_year)
            application_hbx_ids = yield fetch_application_hbx_ids(data_hash)
            yield fetch_applications(application_hbx_ids)
          end

          private

          def validate(params)
            return Failure("Invalid params provided") if params.empty? || params[:additional_params].nil? || params[:additional_params][:assistance_year].nil?
            assistance_year = params[:additional_params][:assistance_year]
            return Failure("Invalid assistance year provided") unless assistance_year.is_a?(Integer)

            Success(assistance_year)
          end

          def fetch_eligible_families(assistance_year)
            result = ::FinancialAssistance::Application.collection.aggregate(
              pipeline_query(assistance_year), allow_disk_use: true
            )

            if result.count.zero?
              Failure("No Applications found with the given criteria")
            else
              Success(result)
            end
          end

          def fetch_application_hbx_ids(data_hash)
            result = data_hash.collect do |hash|
              hash['application_hbx_id']
            end

            if result.empty?
              Failure("No Application hbx_ids found")
            else
              Success(result)
            end
          end

          def fetch_applications(application_hbx_ids)
            result = ::FinancialAssistance::Application.only(:_id, :hbx_id, :aasm_state, :family_id).where(hbx_id: { '$in' => application_hbx_ids })

            if result.empty?
              Failure("No Applications found with the given hbx_ids")
            else
              Success(result)
            end
          end

          def pipeline_query(assistance_year)
            [
                { '$match' => { 'assistance_year' => assistance_year, 'aasm_state' => "determined"} },
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