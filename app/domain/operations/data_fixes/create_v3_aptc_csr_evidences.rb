# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# ::Operations::DataFixes::CreateAptcCsrEvidences.new.call({application_hbx_id: application_hbx_id})
module Operations
  module DataFixes
    # This operation creates APTC CSR evidences.
    class CreateV3AptcCsrEvidences < Operations::DataFixes::CreateV3Evidences
      include Dry::Monads[:do, :result]

      KEY_TITLE_TYPE_MAPPINGS = {"local_mec_evidence" => [:local_mec_evidence, "Local MEC Evidence", 'FinancialAssistance::Evidences::LocalMecEvidence'],
                                 "non_esi_mec_evidence" => [:non_esi_mec_evidence, "Non ESI MEC Evidence", 'FinancialAssistance::Evidences::NonEsiMecEvidence'],
                                 "esi_mec_evidence" => [:esi_mec_evidence, "ESI MEC Evidence", 'FinancialAssistance::Evidences::EsiMecEvidence'],
                                 "income_evidence" => [:income_evidence, "Income Evidence", 'FinancialAssistance::Evidences::IncomeEvidence']}.freeze

      def call(params)
        super
        result = yield create_aptc_csr_evidences(@application)

        Success(result)
      end

      private

      def create_aptc_csr_evidences(application)
        result = []
        application.applicants.each do |applicant|
          applicant_result = [
            application.family_id,
            application.hbx_id,
            application.aasm_state,
            application.created_at,
            application.primary_applicant.person_hbx_id,
            applicant.person_hbx_id,
            applicant.is_applying_coverage
          ]

          ["income_evidence", "esi_mec_evidence", "non_esi_mec_evidence", "local_mec_evidence"].each do |evidence_type|
            evidence = applicant.fetch_v3_evidence(evidence_type)

            if evidence.present?
              result << [*applicant_result, evidence_type, evidence.current_state, "applicant already has #{evidence_type}"]
              next
            end

            if ["esi_mec_evidence", "non_esi_mec_evidence", "local_mec_evidence"].include?(evidence_type)
              result << check_if_applying_coverage(applicant, applicant_result, evidence_type)
            elsif @report
              result << determine_report_line(applicant, applicant_result, evidence_type)
            else
              new_evidence = create_aptc_csr_evidence(applicant, *KEY_TITLE_TYPE_MAPPINGS[evidence_type])
              result << [*applicant_result, evidence_type, new_evidence.current_state, "successfully created #{evidence_type}"]
            end
          end
        end

        Success(result)
      rescue StandardError => e
        Failure("Failed operation with error: #{e.message}")
      end

      def create_aptc_csr_evidence(applicant, key, title, type)
        applicant.build_aptc_csr_eligibility unless applicant.aptc_csr_eligibility.present?
        params = { key: key, title: title, _type: type, current_state: 'unverified', is_satisfied: true }

        evidence = applicant.aptc_csr_eligibility.evidences.build(params)
        update_reason = "Data Migration - V3 Evidence Records"
        evidence.move_to_verified(
          comment: 'Data Migration for post-V3 Evidence implementation Renewal Application',
          reason: update_reason
        )
        evidence.save!
        evidence
      end

      def check_if_applying_coverage(applicant, applicant_result, evidence_type)
        if applicant.is_applying_coverage
          return determine_report_line(applicant, applicant_result, evidence_type) if @report

          new_evidence = create_aptc_csr_evidence(applicant, *KEY_TITLE_TYPE_MAPPINGS[evidence_type])
          [*applicant_result, evidence_type, new_evidence.current_state, "successfully created #{evidence_type}"]
        else
          [*applicant_result, evidence_type, "", "applicant is not applying for coverage"]
        end
      end

      def determine_report_line(applicant, applicant_result, evidence_type)
        message = if applicant.aptc_csr_eligibility.present?
                    "#{evidence_type} not created - report mode enabled"
                  else
                    "aptc_csr_eligibility not found - #{evidence_type} not created"
                  end

        [*applicant_result, evidence_type, '', message]
      end
    end
  end
end
