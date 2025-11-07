# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'

module FinancialAssistance
  module Operations
    module Applications
      module Rrv
        # Operation to generate RRV response report
        class GenerateResponseReport
          include Dry::Monads[:do, :result]

          def call(params)
            assistance_year, from_date = yield validate(params)
            family_ids = yield fetch_family_ids(assistance_year)
            csv_data = yield prepare_for_report(family_ids, assistance_year, from_date)
            file_names = yield generate_csv_file(csv_data)

            Success("RRV report generated successfully at #{file_names}")
          end

          private

          def validate(params)
            return Failure('assistance_year ref missing') unless params[:assistance_year]
            return Failure('from_date is missing') unless params[:from_date]

            Success([params[:assistance_year], params[:from_date]])
          end

          def fetch_family_ids(assistance_year)
            family_ids = ::FinancialAssistance::Application.where(:aasm_state => "determined", :assistance_year => assistance_year, :"applicants.is_ia_eligible" => true).distinct(:family_id)
            Success(family_ids)
          end

          def prepare_for_report(family_ids, assistance_year, from_date)
            array_collection = []
            counter = 0
            total_families = family_ids.count

            family_ids.each do |family_id|
              application = ::FinancialAssistance::Application.where(assistance_year: assistance_year, aasm_state: 'determined', family_id: family_id).max_by(&:created_at)
              primary_person = application.family.primary_person
              application.applicants.each do |applicant|
                fetch_evidence_data(array_collection, family_id, from_date, applicant, primary_person)
              end

              counter += 1
              puts "processed #{counter}/#{total_families} applications" if counter % 100 == 0
            rescue StandardError => e
              puts "Error: message: #{e.message}, backtrace: #{e.backtrace}"
            end
            Success(array_collection)
          end

          def fetch_evidence_data(array_collection, family_id, from_date, applicant, primary_person)
            aptc_csr_eligibility = applicant.aptc_csr_eligibility
            return array_collection << [family_id, primary_person.hbx_id, applicant.person_hbx_id, application.hbx_id, applicant.encrypted_ssn.present?, '', '', '', '', ''] unless aptc_csr_eligibility.present?

            non_esi_evidence = aptc_csr_eligibility.non_esi_mec_evidence
            income_evidence = aptc_csr_eligibility.income_evidence

            [non_esi_evidence, income_evidence].compact.each do |evidence|
              request_result = evidence.request_results.where(:created_at.gte => from_date).last
              workflow_st = evidence.state_histories.where(:created_at.gte => from_date).last
              array_collection << [
                family_id, primary_person.hbx_id, applicant.person_hbx_id, applicant.application.hbx_id, applicant.encrypted_ssn.present?,
                evidence.title, workflow_st&.from_state, workflow_st&.to_state, request_result.present? ? request_result&.result : 'no rrv result found', request_result&.created_at
              ]
            end
          end

          def generate_csv_file(array_collection)
            file_names = []

            array_collection.each_slice(500_000).with_index do |limited_array, index|
              FileUtils.touch("rrv_results_summary_#{index}.csv") unless File.exist?("rrv_results_summary_#{index}.csv")

              csv_content = CSV.generate(force_quotes: true) do |csv|
                csv << ["FamilyID", "PrimaryHbxID", "MemberHbxId", "ApplicationId", "ApplicantWithSsn", "EvidenceType", "CurrentState", "NewState", "ResultFromGateway", "ResultCreatedAt"]
                limited_array.each { |row| csv << row }
              end

              File.write("rrv_results_summary_#{index}.csv", csv_content)
              file_names << "rrv_results_summary_#{index}.csv"
            end
            Success(file_names)
          end
        end
      end
    end
  end
end