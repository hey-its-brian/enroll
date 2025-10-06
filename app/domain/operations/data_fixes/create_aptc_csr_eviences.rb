# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

# ::Operations::DataFixes::CreateAptcCsrEvidences.new.call({application_hbx_id: application_hbx_id})
module Operations
  module DataFixes
    # This operation creates APTC CSR evidences.
    class CreateAptcCsrEvidences
      include Dry::Monads[:do, :result]

      KEY_TITLE_MAPPINGS = {"local_mec_evidence" => [:local_mec, "Local MEC"],
                            "non_esi_evidence" => [:non_esi_mec, "Non ESI MEC"],
                            "esi_evidence" => [:esi_mec, "ESI MEC"],
                            "income_evidence" => [:income, "Income"]}.freeze

      def call(params)
        application_hbx_id = yield validate(params)
        application = yield find_application(application_hbx_id)
        yield validate_application(application)
        result = yield create_evidences(application)

        Success(result)
      end

      private

      def validate(params)
        return Failure("application_hbx_id is missing") unless params[:application_hbx_id].present?

        Success(params[:application_hbx_id])
      end

      def find_application(application_hbx_id)
        application = ::FinancialAssistance::Application.where(hbx_id: application_hbx_id).first
        application ? Success(application) : Failure('Application not found')
      end

      def validate_application(application)
        return Failure("Application should be in determined state") unless application.determined?

        Success(application)
      end

      def create_evidences(application)
        result = []
        application.applicants.each do |applicant|
          applicant_result = [application.family_id, application.hbx_id, application.aasm_state, application.created_at, application.primary_applicant.person_hbx_id, applicant.person_hbx_id, applicant.is_applying_coverage]

          ["income_evidence", "esi_evidence", "non_esi_evidence", "local_mec_evidence"].each do |evidence_type|
            evidence = applicant.fetch_evidence(evidence_type)

            if evidence.present?
              result << [*applicant_result, evidence_type, evidence.aasm_state, "applicant already have #{evidence_type}"]
              next
            end

            if ["esi_evidence", "non_esi_evidence", "local_mec_evidence"].include?(evidence_type)
              if applicant.is_applying_coverage
                new_evidence = create_evidence(applicant, *KEY_TITLE_MAPPINGS[evidence_type])
                result << [*applicant_result, evidence_type, new_evidence.aasm_state, "successfully created #{evidence_type}"]
              else
                result << [*applicant_result, evidence_type, "", "applicant is not applying for coverage"]
              end
            else
              new_evidence = create_evidence(applicant, *KEY_TITLE_MAPPINGS[evidence_type])
              result << [*applicant_result, evidence_type, new_evidence.aasm_state, "successfully created #{evidence_type}"]
            end
          end
        end

        Success(result)
      rescue StandardError => e
        Failure("Failed operation with error: #{e.message}")
      end

      def create_evidence(applicant, key, title)
        params = { key: key, title: title, is_satisfied: true, aasm_state: 'unverified' }
        evidence = case key
                   when :local_mec
                     applicant.build_local_mec_evidence(params)
                   when :esi_mec
                     applicant.build_esi_evidence(params)
                   when :non_esi_mec
                     applicant.build_non_esi_evidence(params)
                   when :income
                     applicant.build_income_evidence(params)
                   else
                     raise ArgumentError, "Unknown evidence type: #{key}"
                   end

        update_reason = "Data Migration - Evidence Records"
        evidence.verification_histories.build(action: "Data Migration", update_reason: update_reason, updated_by: "Admin")
        evidence.move_to_verified
        evidence.save!
        evidence
      end
    end
  end
end
