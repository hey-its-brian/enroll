# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# Syntax:
# Operations::FinancialAssistance::BulkExtendEvidencesDueOn.new.call({application_hbx_ids: hbx_ids, evidence_types: ["esi_evidence"], extension_days: 30})
# Operations::FinancialAssistance::BulkExtendEvidencesDueOn.new.call({application_hash: {"#{application.hbx_id}": [applicant.person_hbx_id, applicant2.person_hbx_id]}, evidence_types: ["income_evidence"], extension_days: 30})
# Report
# Fetch the report from the root path bulk_extend_evidence_due_on_report_2021_09_29.csv
module Operations
  module FinancialAssistance
    # Bulk FedHubCalls for verification types
    class BulkExtendEvidencesDueOn
      include Dry::Monads[:do, :result]

      RESTRICTED_EVIDENCE_TYPES = ['non_esi_evidence', 'esi_evidence', 'local_mec_evidence'].freeze

      def call(params)
        applications_data, evidence_types, extension_days = yield validate(params)
        @csv_content = []
        yield process_application_hbx_ids(applications_data, evidence_types, extension_days) if applications_data.is_a?(Array)
        yield process_application_hash(applications_data, evidence_types, extension_days) if applications_data.is_a?(Hash)
        yield generate_csv

        Success(@csv_content)
      end

      private

      def validate(params)
        return Failure('No hbx_ids provided') unless params[:application_hbx_ids].present? || params[:application_hash].present?
        return Failure('No evidence_types provided') unless params[:evidence_types].present?
        return Failure('no extension_days provided') unless params[:extension_days].present?
        return Failure('Currently this feature is only enabled for income evidences') if params[:evidence_types].any? { |evidence_type| RESTRICTED_EVIDENCE_TYPES.include?(evidence_type) }

        Success([params[:application_hbx_ids] || params[:application_hash], params[:evidence_types], params[:extension_days]])
      end

      def process_application_hbx_ids(application_hbx_ids, evidence_types, extension_days)
        applications = ::FinancialAssistance::Application.where(hbx_id: application_hbx_ids)

        return Failure("Applications not found for hbx_ids: #{application_hbx_ids}") unless applications.present?

        applications.each do |application|
          applicants = application.applicants
          process_applicants(applicants, evidence_types, extension_days)
        end

        Success(applications)
      end

      def process_application_hash(applications_data, evidence_types, extension_days)
        applications = []
        applications_data.each do |application_hbx_id, applicant_person_hbx_ids|
          application = ::FinancialAssistance::Application.where(hbx_id: application_hbx_id).first
          unless application.present?
            @csv_content << ["", application_hbx_id, applicant_person_hbx_ids, evidence_types, "Application not found"]
            next
          end

          applicants = application.applicants.where(:person_hbx_id.in => applicant_person_hbx_ids)

          unless applicants.present?
            @csv_content << ["", application_hbx_id, applicant_person_hbx_ids, evidence_types, "Applicants not found"]
            next
          end

          process_applicants(applicants, evidence_types, extension_days)
        end

        Success(applications)
      end

      def extend_due_date(applicant, evidence_types, extension_days)
        application = applicant.application
        evidence_types.each do |evidence_type|
          evidence = applicant.send(evidence_type)
          result = Operations::FinancialAssistance::ExtendEvidenceDueOn.new.call({evidence: evidence, extension_days: extension_days})
          @csv_content << if result.success?
                            [application.primary_applicant.person_hbx_id, application.hbx_id, applicant.person_hbx_id, evidence_type, result.value!]
                          else
                            [application.primary_applicant.person_hbx_id, application.hbx_id, applicant.person_hbx_id, evidence_type, result.failure]
                          end
        end
      end

      def process_applicants(applicants, evidence_types, extension_days)
        applicants.each do |applicant|
          extend_due_date(applicant, evidence_types, extension_days)
        end

        Success(true)
      end

      def generate_csv
        return Failure('No data to generate CSV') if @csv_content.empty?

        csv_file_path = "#{Rails.root}/bulk_extend_evidence_due_on_report_#{TimeKeeper.date_of_record.strftime('%Y_%m_%d')}.csv"
        CSV.open(csv_file_path, 'w') do |csv|
          csv << ["Primary Person HBX ID", "Application HBX ID", "Applicant Person HBX ID", "Evidence Type", "Status"]
          @csv_content.each do |row|
            csv << row
          end
        end

        Success("CSV file generated at #{csv_file_path}")
      end
    end
  end
end
