# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# Syntax:
# Operations::People::BulkHubCallsForEvidences.new.call({hbx_ids: hbx_ids, evidence_types: ["esi_evidence"]})
# Report
# Fetch the report from the root path bulk_evidences_hub_call_report_2021_09_29.csv
module Operations
  module FinancialAssistance
    # Bulk FedHubCalls for verification types
    class BulkHubCallsForEvidences
      include Dry::Monads[:do, :result]

      RESTRICTED_EVIDENCE_TYPES = ['income_evidence', 'non_esi_evidence'].freeze

      def call(params)
        params = yield validate(params)
        array_collection = yield start(params)
        result = yield generate_csv(array_collection)

        Success(result)
      end

      private

      def validate(params)
        return Failure('No hbx_ids provided') if params[:hbx_ids].empty?
        return Failure('No evidence_types provided') if params[:evidence_types].empty?
        return Failure('Currently this feature is only enabled for esi and local MEC evidences') if params[:evidence_types].any? { |evidence_type| RESTRICTED_EVIDENCE_TYPES.include?(evidence_type) }

        Success(params)
      end

      def validate_and_collect_status(result,record, message)
        unless record.present?
          result << message
          return false
        end

        true
      end

      def start(params)
        hbx_ids = params[:hbx_ids]
        evidence_types = params[:evidence_types]
        result = []

        hbx_ids.each do |hbx_id|
          process_hbx_id(hbx_id, evidence_types, result)
        end

        Success(result)
      end

      def process_hbx_id(hbx_id, evidence_types, result)
        person = Person.by_hbx_id(hbx_id).first
        return unless validate_and_collect_status(result, person, ["", hbx_id, "", "Person not found"])
        return unless validate_and_collect_status(result, person.families, ["", hbx_id, "", "Families not found"])

        person.families.each do |family|
          process_family(family, hbx_id, evidence_types, result)
        end
      end

      def process_family(family, hbx_id, evidence_types, result)
        application = family.latest_determined_faa_application
        return unless validate_and_collect_status(result, application, ["", hbx_id, "", "Determined application not found"])

        applicant = application.applicants.where(person_hbx_id: hbx_id).first
        return unless validate_and_collect_status(result, applicant, [application.hbx_id, hbx_id, "", "respective applicant with person hbx id was not found"])

        evidences = evidence_types.collect { |evidence_type| applicant.send(evidence_type) }.compact.flatten
        return unless validate_and_collect_status(result, evidences, [application.hbx_id, hbx_id, "", "#{evidence_types} are not found"])

        process_evidences(evidences, application.hbx_id, hbx_id, result)
      end

      def process_evidences(evidences, application_hbx_id, hbx_id, result)
        evidences.each do |evidence|
          status = process_evidence(evidence)
          result << [application_hbx_id, hbx_id, evidence.key, status]
        end
      end

      def process_evidence(evidence)
        return "#{evidence} is not in outstanding state to trigger hub call " unless evidence.outstanding?

        result = evidence.request_determination("Hub Request Initiated", "Bulk Hub Call", "Admin")

        result ? "Hub call initiated for #{evidence.key}" : "Failed to initiate hub call for #{evidence}"
      end

      def generate_csv(array_collection)
        field_names = ["Application HBX ID", "Person HBX ID", "Evidence Type", "Status"]
        file_name = "#{Rails.root}/bulk_evidences_hub_call_report_#{Date.today.strftime('%Y_%m_%d')}.csv"
        FileUtils.touch(file_name) unless File.exist?(file_name)

        csv_content = CSV.generate(force_quotes: true) do |csv|
          csv << field_names
          array_collection.each { |row| csv << row }
        end

        File.write(file_name, csv_content)

        Success("Finished Bulk Hub Call, fetch the report from the root path #{file_name}")
      rescue StandardError => e
        Failure("Failed to generate CSV report because of #{e.message}")
      end
    end
  end
end


