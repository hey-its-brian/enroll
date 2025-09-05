# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module Operations
  # This class takes in args of a year and removes duplicate applicant relationships
  class RemoveDuplicateFaaRelationships
    include Dry::Monads[:do, :result]

    def call(params)
      year                                      = yield validate(params)
      applications_with_duplicate_relationships = yield fetch_duplicate_relationship_app_ids(year)
      filtered_applications                     = yield filter_applications(applications_with_duplicate_relationships)
      result                                    = yield remove_duplicate_relationships(filtered_applications)

      Success(result)
    end

    private

    def validate(params)
      return Failure("Year is required") unless params[:year].present?
      Success(params[:year].to_i)
    end

    def fetch_duplicate_relationship_app_ids(year)
      duplicate_apps = ::FinancialAssistance::Application.by_year(year).where(aasm_state: 'draft').collection.aggregate([
      { "$unwind": "$relationships" },

      { "$group": {
        _id: {
          application_id: "$_id",
          applicant_id: "$relationships.applicant_id",
          relative_id: "$relationships.relative_id"
        },
        count: { "$sum": 1 }
      }},
      { "$match": { count: { "$gt": 1 } } },
      { "$group": { _id: "$_id.application_id" } }
    ])

      Success(duplicate_apps)
    end

    def filter_applications(application_ids)
      filtered_apps = application_ids.filter_map do |app_id|
        application = ::FinancialAssistance::Application.find(app_id)
        next unless application&.family
        application if is_most_recent_draft_app?(application) && !has_duplicate_applicants?(application)
      end
      Success(filtered_apps)
    end

    def remove_duplicate_relationships(applications)
      date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
      updated_count = 0
      filepath = Rails.root.join("removed_duplicate_faa_relationships_#{date}.csv")

      CSV.open(filepath, 'w', force_quotes: true) do |csv|
        csv << ['Primary Person Hbx Id', 'Application Hbx Id', 'Duplicate Relationship Kind', 'Duplicate Relationship Relative Id', 'Created At']

        applications.each do |application|
          family = application.family
          duplicate_groups = application.relationships.group_by { |r| [r.applicant_id, r.relative_id] }
                                        .values
                                        .select { |group| group.length > 1 }

          next if duplicate_groups.empty?
          duplicate_groups.each do |group|
            group.drop(1).each do |relationship_to_delete|
              csv << [family.primary_person.hbx_id, application.hbx_id, relationship_to_delete.kind, relationship_to_delete.relative_id, relationship_to_delete.created_at]
              relationship_to_delete.delete
              updated_count += 1
            end

          end
        rescue Mongoid::Errors::DocumentNotFound => e
          Rails.logger.error "Could not find person or relationship for data: #{application.hbx_id}. Error: #{e.message}"
        rescue StandardError => e
          Rails.logger.error "Failed to process duplicate relationship for application #{application.hbx_id}: #{e.message}"
        end
      end
      Success("Successfully removed #{updated_count} duplicate relationships and generated CSV file: #{filepath}")
    end

    def has_duplicate_applicants?(application)
      application.applicants.group_by(&:person_hbx_id).any? { |_hbx_id, applicants| applicants.size > 1 }
    end

    def is_most_recent_draft_app?(application)
      application == application.family.most_recent_and_draft_financial_assistance_application
    end
  end
end