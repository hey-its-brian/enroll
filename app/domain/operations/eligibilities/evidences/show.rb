# app/domain/operations/eligibilities/evidences/documents/index.rb
# frozen_string_literal: true

module Operations
  module Eligibilities
    module Evidences
      # Show operation handles retrieving documents for evidence from applications
      class Show
        include Dry::Monads[:do, :result]

        # Retrieves documents for evidence verification
        #
        # @param params [Hash] parameters for filtering documents
        # @param evidence [Evidence] the evidence record
        # @return [Dry::Monads::Result] Success with result hash or Failure with error message
        def call(params:, evidence:)
          validated_params = yield validate(params, evidence)
          all_applications = yield fetch_applications(validated_params[:family_id])
          years = yield fetch_assistance_years(all_applications)
          filtered_applications = yield filter_applications(all_applications, validated_params[:selected_year], years)
          matching_applications = yield fetch_matching_applications(filtered_applications, evidence)

          Success(
            years: years,
            selected_year: validated_params[:selected_year],
            applications: matching_applications[:applications],
            bs4: true
          )
        end

        private

        def validate(params, evidence)
          return Failure("Evidence not found") if evidence.blank?
          return Failure("Family ID is required") if params[:family_id].blank?

          validated_params = {
            family_id: params[:family_id],
            selected_year: params.dig(:filter, :year).presence
          }

          Success(validated_params)
        end

        def fetch_assistance_years(applications)
          years = applications.map(&:assistance_year)&.uniq&.compact&.sort&.reverse

          return Failure("No applications found for family") if years&.empty?

          Success(years)
        end

        def fetch_applications(family_id)
          qhp_applications = fetch_qhp_applications(family_id)
          faa_applications = fetch_faa_applications(family_id)
          all_applications = qhp_applications + faa_applications

          Success(all_applications)
        end

        def fetch_qhp_applications(family_id)
          query = ::IndividualMarket::Application.where(family_id: family_id)

          query.to_a
        end

        def fetch_faa_applications(family_id)
          query = ::FinancialAssistance::Application.where(family_id: family_id)

          query.to_a
        end

        def filter_applications(all_applications, selected_year, years)
          year = selected_year.present? ? selected_year.to_i : years.first.to_i

          Success(all_applications.select { |app| app.assistance_year == year })
        end

        def fetch_matching_applications(applications, evidence)
          evidence_key = evidence.key.to_s
          eligibility_key = evidence.eligibility.key

          matching_applications = applications.select do |app|
            app.applicants.any? do |applicant|
              eligibility = applicant.respond_to?(eligibility_key) ? applicant.send(eligibility_key) : nil
              eligibility&.evidences&.any? { |ev| ev.key.to_s == evidence_key }
            end
          end

          sorted_applications = matching_applications.sort_by { |app| app.submitted_at || Time.at(0) }.reverse

          Success(applications: sorted_applications)
        end
      end
    end
  end
end
