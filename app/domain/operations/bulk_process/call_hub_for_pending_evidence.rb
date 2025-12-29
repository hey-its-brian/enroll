# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'csv'
require 'fileutils'

module Operations
  module BulkProcess
    # Bulk FedHub calls for SSA evidence with pending status
    #
    # Usage:
    #   Operations::BulkProcess::CallHubForPending.new.call(
    #     family_ids: [BSON::ObjectId('...'), ...],
    #     evidence_type: 'social_security_number_evidence'
    #     reason_for_verification_request: 'Reason text'
    #   )
    #
    # Result:
    #   Success(String) => path to CSV report
    #   Failure(String) => error message
    class CallHubForPendingEvidence
      include Dry::Monads[:do, :result]

      CSV_HEADERS = [
        'Application Type',
        'Application HBX ID',
        'Primary HBX ID',
        'Evidence Type',
        'Status'
      ].freeze

      REPORT_PREFIX = 'bulk_evidences_hub_call_report'

      def call(params)
        family_ids, evidence_type, @reason_for_verification_request = yield validate(params)
        rows = yield process_families(family_ids, evidence_type)
        result = yield generate_csv(rows)

        Success(result)
      end

      private

      def validate(params)
        return Failure('params must be a Hash') unless params.is_a?(Hash)

        family_ids = Array(params[:family_ids]).compact
        evidence_type = params[:evidence_type].to_s
        reason_for_verification_request = params[:reason_for_verification_request]

        return Failure('family_ids must be present') if family_ids.empty?
        return Failure('evidence_type must be present') if evidence_type.empty?
        return Failure('reason_for_verification_request must be present') if reason_for_verification_request.empty?

        Success([family_ids, evidence_type, reason_for_verification_request])
      end

      # Iterates families and initiates Hub calls for eligible applicants
      def process_families(family_ids, evidence_type)
        rows = []

        Family.where(:id.in => family_ids).each do |family|
          process_family(family, evidence_type, rows)
        rescue StandardError => e
          rows << ['N/A', 'N/A', 'N/A', evidence_type, 'N/A', "error processing family #{family.id}: #{e.message}"]
        end

        Success(rows)
      end

      def process_family(family, evidence_type, rows)
        application      = family.latest_application
        application_type = family.application_type

        return rows << build_error_row('N/A', 'N/A', 'N/A', evidence_type, 'no latest application found') if application.blank?

        primary_hbx_id = fetch_applicant_hbx_id(application.primary_applicant, application_type)
        return rows << build_error_row(application_type, application.hbx_id, 'N/A', evidence_type, 'primary HBX ID not available') if primary_hbx_id.blank?

        eligible_applicants = fetch_eligible_applicants(application, evidence_type)
        return rows << build_error_row(application_type, application.hbx_id, primary_hbx_id, evidence_type, 'no eligible applicants for hub call') if eligible_applicants.blank?

        eligible_hbx_ids = eligible_hbx_ids_for(eligible_applicants, application_type)
        return rows << build_error_row(application_type, application.hbx_id, primary_hbx_id, evidence_type, 'eligible applicants missing HBX IDs') if eligible_hbx_ids.blank?

        before_hub_call_evidence_state = evidence_states_for(eligible_applicants, evidence_type)
        result = initiate_hub_call(application, eligible_hbx_ids)

        rows << if result.success?
                  [application_type, application.hbx_id, primary_hbx_id, evidence_type, before_hub_call_evidence_state.join('; '), "Hub call initiated for applicants: #{eligible_hbx_ids.join(', ')}"]
                else
                  [application_type, application.hbx_id, primary_hbx_id, evidence_type, before_hub_call_evidence_state.join('; '), "Failed to initiate hub call: #{result.failure}"]
                end
      end

      def eligible_hbx_ids_for(applicants, application_type)
        applicants.map { |appl| fetch_applicant_hbx_id(appl, application_type) }.compact
      end

      def evidence_states_for(applicants, evidence_type)
        applicants.flat_map(&:eligibilities)
                  .flat_map(&:evidences)
                  .select { |ev| ev.key == evidence_type }
                  .map(&:current_state)
      end

      def initiate_hub_call(application, eligible_hbx_ids)
        Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification.new.call(
          application: application,
          request_hbx_ids: eligible_hbx_ids,
          call_type: 'hub_call',
          updated_by: 'Admin',
          reason_for_verification_request: @reason_for_verification_request
        )
      end

      def build_error_row(app_type, app_hbx_id, primary_hbx_id, evidence_type, message)
        [app_type, app_hbx_id, primary_hbx_id, evidence_type, 'N/A', message]
      end

      def fetch_eligible_applicants(application, evidence_type)
        application.applicants.where(
          :is_applying_coverage => false,
          :eligibilities.elem_match => {
            :evidences.elem_match => {
              key: evidence_type,
              current_state: :pending
            }
          }
        )
      end

      # Resolves applicant HBX ID based on application type
      def fetch_applicant_hbx_id(applicant, application_type)
        return nil if applicant.blank?

        case application_type
        when 'qhp'
          applicant.hbx_id
        when 'faa'
          applicant.person_hbx_id
        end
      end

      # generates CSV report from the processed rows
      def generate_csv(rows)
        date = DateTime.now
        file_name = File.join(Rails.root.to_s, "#{REPORT_PREFIX}_#{date.strftime('%Y_%m_%d_%H_%M_%S')}.csv")

        FileUtils.touch(file_name) unless File.exist?(file_name)

        csv_content = CSV.generate(force_quotes: true) do |csv|
          csv << CSV_HEADERS
          rows.each { |row| csv << row }
        end

        File.write(file_name, csv_content)
        Success("Finished Bulk Hub Call. Report: #{file_name}")
      rescue StandardError => e
        Failure("Failed to generate CSV report: #{e.message}")
      end
    end
  end
end