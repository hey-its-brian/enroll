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
            "ApplicationStatus (CurrentState)",
            "PredecessorApplicationHbxId",
            "ApplicantEligibilities"
          ].freeze

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
            [
              application&.primary_applicant&.person&.hbx_id,
              application.hbx_id,
              application.current_state.to_s,
              application.family&.fetch_last_determined_application_from(application.id, application.assistance_year.pred)&.hbx_id,
              application_eligibilities(application)
            ]
          end

          def application_eligibilities(application)
            non_applicant_ids = application.non_applicants.map(&:family_member_id)
            applicants = application.applicants.reject { |applicant| non_applicant_ids.include?(applicant.family_member_id) }
            eligibilities = []
            eligibilities << "Not Applying" if non_applicant_ids.any?
            return eligibilities.join(", ") if applicants.empty?

            eligibility = if applicants.all?(&:is_qhp_eligible)
                            "QHP Eligible"
                          elsif applicants.none?(&:is_qhp_eligible)
                            "QHP Ineligible"
                          else
                            "Mixed QHP Eligibilities"
                          end
            eligibilities << eligibility

            eligibilities.join(", ")
          rescue StandardError => e
            "Error determining eligibilities: #{e.message}"
          end
        end
      end
    end
  end
end
