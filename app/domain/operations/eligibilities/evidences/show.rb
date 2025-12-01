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
        def call(params:, family_member:, evidence:)
          validated_params = yield validate(params, evidence)
          all_applications = yield fetch_applications(validated_params[:family_id])
          years = yield fetch_assistance_years(all_applications)
          filtered_applications = yield filter_applications(all_applications, validated_params[:selected_year], years)
          matching_applications = yield fetch_matching_applications(filtered_applications, evidence)
          application_evidence_mapping = yield fetch_matching_evidence_for_applications(matching_applications[:applications], family_member, evidence)
          renewal_current_and_previous_application_ids = yield fetch_renewal_current_and_previous_application_ids(all_applications, evidence)

          Success(
            years: years,
            selected_year: validated_params[:selected_year],
            applications: matching_applications[:applications],
            application_evidence_mapping: application_evidence_mapping,
            bs4: true,
            renewal_current_and_previous_application_ids: renewal_current_and_previous_application_ids
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
          query = ::IndividualMarket::Application.cancelled_or_determined_by_family(family_id)

          query.to_a
        end

        def fetch_faa_applications(family_id)
          query = ::FinancialAssistance::Application.cancelled_or_determined_by_family(family_id)

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

        def fetch_matching_evidence_for_applications(applications, family_member, evidence)
          mapping = {}
          evidence_key = evidence.key.to_s
          eligibility_key = evidence.eligibility.key
          applications.each do |app|
            applicant = app.applicants.detect { |a| a.family_member_id.to_s == family_member.id.to_s }
            next unless applicant

            eligibility = applicant.eligibilities.where(key: eligibility_key).first
            next unless eligibility&.evidences

            matching_evidence = eligibility.evidences.detect { |ev| ev.key.to_s == evidence_key }
            mapping[app.hbx_id] = matching_evidence
          end

          Success(mapping)
        end

        def fetch_renewal_current_and_previous_application_ids(all_applications, evidence)
          evidence_key = evidence.key.to_s
          eligibility_key = evidence.eligibility.key
          family_member_id = evidence.eligibility&.eligible&.family_member_id.to_s
          recent_years = calculate_recent_years

          application_ids = all_applications
                            .select { |app| eligible_application?(app, evidence_key, eligibility_key, family_member_id, recent_years) }
                            .reverse
                            .map(&:hbx_id)

          Success(application_ids)
        end

        def calculate_recent_years
          current_year = TimeKeeper.date_of_record.year
          [current_year + 1, current_year, current_year - 1]
        end

        def eligible_application?(application, evidence_key, eligibility_key, family_member_id, recent_years)
          # Early return conditions
          return false unless has_matching_applicant?(application, family_member_id)
          return false unless has_recent_year?(application, recent_years)
          return false unless application_determined?(application)

          # Check for matching evidence
          applicant = find_matching_applicant(application, family_member_id)
          eligibility = find_matching_eligibility(applicant, eligibility_key)
          return false unless eligibility&.evidences

          has_matching_evidence?(eligibility, evidence_key)
        end

        def has_matching_applicant?(application, family_member_id)
          application.applicants.any? { |a| a.family_member_id.to_s == family_member_id.to_s }
        end

        def find_matching_applicant(application, family_member_id)
          application.applicants.detect { |a| a.family_member_id.to_s == family_member_id.to_s }
        end

        def find_matching_eligibility(applicant, eligibility_key)
          applicant.eligibilities.where(key: eligibility_key).first
        end

        def has_matching_evidence?(eligibility, evidence_key)
          eligibility.evidences.any? { |ev| ev.key.to_s == evidence_key }
        end

        def has_recent_year?(application, recent_years)
          recent_years.include?(application.assistance_year)
        end

        def application_determined?(application)
          case application
          when ::FinancialAssistance::Application
            application.aasm_state.to_s == 'determined'
          when ::IndividualMarket::Application
            application.current_state.to_s == 'determined'
          else
            false
          end
        end
      end
    end
  end
end
