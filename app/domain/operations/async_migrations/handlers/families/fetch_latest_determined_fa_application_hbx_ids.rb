# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        # Fetches families with determined applications.
        # This Operation can be retriggered multiple times, and it will only return families that do not have determined applications that migrated recently.
        class FetchLatestDeterminedFAApplicationHbxIds
          include Dry::Monads[:do, :result]

          def call(params)
            assistance_year = yield validate(params)
            data_hash = yield fetch_latest_app_for_each_family(assistance_year)
            yield fetch_ids(data_hash, params)
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

            Success(result)
          end

          def fetch_ids(data_hash, params)
            result = if params.dig(:additional_params, :data_type) == 'family_ids'
                       data_hash.collect do |hash|
                         hash['family_id']
                       end
                     else
                       data_hash.collect do |hash|
                         hash['application_bson_id']
                       end
                     end

            Success(result)
          end

          def pipeline_query(assistance_year)
            [
                { '$match' => { 'assistance_year' => assistance_year, 'aasm_state' => "determined" } },
                { '$sort' => { 'submitted_at' => -1 } },
                { '$group' => { '_id' => '$family_id', 'application_bson_id' => { '$first' => '$_id' }, 'application_origin' => { '$first' => '$origin' } } },
                { '$match' => { 'application_origin' => { '$ne' => 'migration'} } },
                { '$project' => { '_id' => 0, 'application_bson_id' => 1, 'family_id' => '$_id' } }
            ]
          end
        end
      end
    end
  end
end