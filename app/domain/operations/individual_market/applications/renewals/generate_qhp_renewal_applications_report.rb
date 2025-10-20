# frozen_string_literal: true

require 'csv'
require 'dry/monads'
require 'dry/monads/do'

module Operations
  module IndividualMarket
    module Applications
      module Renewals
        # generates report for qhp renewal applications, including current_state, etc.
        class GenerateQhpRenewalApplicationsReport
          include Dry::Monads[:result, :do]

          QHP_RENEWAL_APPLICATION_REPORT_CSV_HEADERS = [
            "PrimaryHbxId",
            "ApplicationHbxId",
            "AllApplicantHbxIds",
            "ApplicationStatus (CurrentState)",
            "IndividualApplicantEligibilities",
            "IndividualApplicantIneligibilityReasons"
          ].freeze

          QHP_INELIGIBILITY_REASONS_BY_BASIS_KIND = {
            'is_alive' => 'Applicant has been marked as deceased',
            'state_resident' => 'Applicant is not a resident',
            'lawfully_present_in_us' => 'Applicant is not lawfully present in the US',
            'not_incarcerated' => 'Applicant is incarcerated'
          }.freeze

          def call(params)
            assistance_year  = yield validate(params)
            applications     = yield fetch_applications(assistance_year)
            result           = yield generate_report(applications)

            Success(result)
          end

          private

          def validate(params)
            assistance_year = params[:assistance_year]
            return Failure("Invalid assistance year: #{assistance_year}.") unless assistance_year.is_a?(Integer) && assistance_year >= 1000 && assistance_year <= 9999
            Success(assistance_year)
          end

          def fetch_applications(assistance_year)
            applications = ::IndividualMarket::Application.where(
              is_renewal: true,
              assistance_year: assistance_year
            )
            applications.present? ? Success(applications) : Failure("No applications found for assistance year #{assistance_year}")
          end

          def generate_report(applications)
            file_path = "#{Rails.root}/qhp_renewal_application_report_#{TimeKeeper.date_of_record.strftime('%m_%d_%Y')}.csv"
            logger = Logger.new("#{Rails.root}/log/qhp_renewal_application_report_logger.log")
            logger.info "Total number of qhp applications to be processed: #{applications.count}"
            total_processed = 0

            CSV.open(file_path, 'w', force_quotes: true) do |report_csv|
              report_csv << QHP_RENEWAL_APPLICATION_REPORT_CSV_HEADERS
              applications.each do |application|
                report_csv << generate_row(application)
                total_processed += 1
                logger.info "Processed qhp application with hbx_id: #{application.hbx_id}"
              rescue StandardError => e
                logger.info "Error raised while processing qhp application with hbx_id: #{application.hbx_id}, error: #{e.message}, backtrace: #{e.backtrace.join("\n")}"
              end
            end

            Success("Successfully captured #{total_processed}/#{applications.count} total qhp application states successfully in #{file_path}")
          end

          def generate_row(application)
            non_applicant_ids = application.non_applicants.map(&:hbx_id)

            [
              application&.primary_applicant&.person&.hbx_id,
              application.hbx_id,
              application.applicants.map(&:hbx_id).join("\n"),
              application.current_state.to_s,
              application_eligibilities(application, non_applicant_ids),
              ineligibility_reasons(application, non_applicant_ids)
            ]
          end

          def application_eligibilities(application, non_applicant_ids)
            eligibilities = []

            application.applicants.each do |applicant|
              eligibilities << if non_applicant_ids.include?(applicant.hbx_id)
                                 "#{applicant.hbx_id}: Not Applying"
                               else
                                 "#{applicant.hbx_id}: #{applicant.is_qhp_eligible ? 'QHP Eligible' : 'QHP Ineligible'}"
                               end
            end

            eligibilities.join("\n")
          rescue StandardError => e
            "Error determining eligibilities: #{e.message}"
          end

          def ineligibility_reasons(application, non_applicant_ids)
            application.applicants.map do |applicant|
              # skip if applicant is QHP eligible or a non-applicant
              next if applicant.is_qhp_eligible || non_applicant_ids.include?(applicant.hbx_id)

              qhp_determination = applicant&.individual_market_eligibility&.qhp_determination
              all_applicant_reasons << "#{applicant.hbx_id}: No valid QHP determination" && next unless qhp_determination

              "#{applicant.hbx_id}: #{add_individual_reasons_from_basis(qhp_determination)}"
            end.compact.join("\n")
          rescue StandardError => e
            "Error extracting ineligibility reasons: #{e.message}"
          end

          def add_individual_reasons_from_basis(qhp_determination)
            qhp_determination.bases.map do |basis|
              # ignore if basis is satisfied (valid/eligible)
              next if basis.is_satisfied

              QHP_INELIGIBILITY_REASONS_BY_BASIS_KIND[basis.basis_kind]
            end.compact.join(', and ')
          end
        end
      end
    end
  end
end
