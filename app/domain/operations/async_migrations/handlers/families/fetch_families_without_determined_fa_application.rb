# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        # Fetch
        class FetchFamiliesWithoutDeterminedFAApplication
          include Dry::Monads[:do, :result]

          def call(params)
            assistance_year = yield validate(params)
            applications = yield fetch_families_with_latest_determined_fa_application(assistance_year)
            families_without_determined_fa_applications = yield fetch_families_without_determined_fa_applications(applications)
            filtered_family_ids = yield fetch_families_with_enrollment_in_current_year(families_without_determined_fa_applications, assistance_year)
            filtered_family_ids = yield remove_families_with_any_qhp_application(filtered_family_ids)
            yield fetch_families_as_object(filtered_family_ids)
          end

          private

          def validate(params)
            return Failure("Invalid params provided") if params.empty? || params[:additional_params].nil? || params[:additional_params][:assistance_year].nil?
            assistance_year = params[:additional_params][:assistance_year]
            return Failure("Invalid assistance year provided") unless assistance_year.is_a?(Integer)

            Success(assistance_year)
          end

          def fetch_families_with_latest_determined_fa_application(assistance_year)
            result = ::Operations::AsyncMigrations::Handlers::Families::FetchLatestDeterminedFAApplicationHbxIds.new.call(
              additional_params: { assistance_year: assistance_year }
            )

            Success(result)
          end

          def fetch_families_without_determined_fa_applications(applications)
            Success(Family.only(:_id).where(:id.nin => applications.pluck(:family_id)))
          end

          def fetch_families_with_enrollment_in_current_year(families, assistance_year)
            family_ids = families.pluck(:_id)

            filtered_family_ids = HbxEnrollment.collection.aggregate(
              [
                {'$match' => { 'family_id' => { '$in' => family_ids },
                               'effective_on' => {'$gte' => Date.new(assistance_year), '$lte' => Date.new(assistance_year).end_of_year},
                               'aasm_state' => { '$in' => ['coverage_selected', 'coverage_canceled', 'coverage_terminated', 'auto_renewing', 'unverified']}}},
                {'$project' => { 'family_id' => 1, '_id' => 0 }}
              ], allow_disk_use: true
            ).to_a.map do |hash|
              hash['family_id']
            end.uniq

            Success(filtered_family_ids)
          end

          def remove_families_with_any_qhp_application(filtered_family_ids)
            family_ids_with_qhp = ::IndividualMarket::Application.only(:family_id).where(current_state: :determined).pluck(:family_id)
            Success(filtered_family_ids - family_ids_with_qhp)
          end

          def fetch_families_as_object(filtered_family_ids)
            Success(Family.only(:_id).where(:id.in => filtered_family_ids))
          end
        end
      end
    end
  end
end