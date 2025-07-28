# frozen_string_literal: true

module Operations
  module AsyncMigrations
    module Handlers
      module Families
        # Fetches families with determined applications.
        class MigrateTaxHouseholdGroup
          include Dry::Monads[:do, :result]
          include EventSource::Command
          include ::ResourceRegistryHelper

          def call(params)
            family_id = yield validate(params)
            family = yield find_family(family_id)
            result = yield migrate(family)
            yield publish(result)

            Success(result)
          end

          private

          def validate(params)
            return Failure('family_id is expected in BSON format') unless BSON::ObjectId.legal?(params[:document_id])

            Success(params[:document_id].to_s)
          end

          def find_family(family_id)
            family_find_result = ::Operations::Families::Find.new.call(id: BSON::ObjectId(family_id))
            return family_find_result if family_find_result.failure?

            Success(family_find_result.success)
          end

          def migrate(family)
            return Success([family.hbx_assigned_id, "No Tax Household Groups to migrate"]) if family.tax_household_groups.empty?

            result = family.tax_household_groups.collect do |tax_household_group|
              application_hbx_id = tax_household_group.application_hbx_id
              next [family.hbx_assigned_id, tax_household_group.hbx_id, "Tax Household Group does not have application hbx id"] unless application_hbx_id.present?

              application = ::FinancialAssistance::Application.only(:_id, :hbx_id, :aasm_state).where(hbx_id: application_hbx_id).first
              next [family.hbx_assigned_id, tax_household_group.hbx_id, "FAA Application not found for hbx_id: #{application_hbx_id}"] unless application

              application_gid = application.to_global_id.to_s

              tax_household_group.set(application_gid: application_gid)
              [family.hbx_assigned_id, tax_household_group.hbx_id, "Tax Household Group migration successful"]
            end

            Success(result)
          rescue StandardError => e
            Failure("Error migrating Tax Household Group for family #{family.hbx_assigned_id}: #{e.message}")
          end

          def publish(rows)
            csv_headers = ["Family HBX ID",
                           "Tax Household Group HBX ID",
                           "Migration Result"]

            result = rows.collect do |row|
              event = event("events.migration_results.enqueue_result", attributes: {csv_file_name: "family_with_tax_household_group_report", csv_headers: csv_headers, csv_row: row})
              if event.success?
                event.success.publish
              else
                false
              end
            end

            result.all?(true) ? Success("All evidence migration events published successfully") : Failure("Some evidence migration events failed to publish")
          end
        end
      end
    end
  end
end
