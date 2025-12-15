# frozen_string_literal: true

require 'dry/monads'
require 'dry/monads/do'
require 'csv'

module Operations
  # This operation triggers an SSAVLP Verification Hub call for applicants who did not receive a hub response on application determination
  class CallHubForNoSsnUsCitizenApplicants
    include Dry::Monads[:do, :result]

    def call
      families = yield fetch_eligible_families
      process_applicants(families)
    end

    private

    def fetch_eligible_families
      assistance_years = [2025, 2026]

      fa_results = ::FinancialAssistance::Application.collection.aggregate([
        {
          "$match": {
            aasm_state: "determined",
            :assistance_year => { "$in" => assistance_years },
            applicants: {
              "$elemMatch": { encrypted_ssn: nil, citizen_status: 'us_citizen' }
            }
          }
        },
        {
          "$project": { family_id: 1, submitted_at: 1 }
        }
      ])

      im_results = Mongoid.default_client[:sbm_applications].aggregate([
        {
          "$match": {
            _type: "IndividualMarket::Application",
            "assistance_year" => { "$in" => assistance_years },
            "applicants": {
              "$elemMatch": {
                "demographics.encrypted_ssn": nil,
                "demographics.citizen_status": 'us_citizen'
              }
            }
          }
        },
        { "$project": { family_id: 1, submitted_at: 1 } }
      ])

      combined_results = (fa_results.to_a + im_results.to_a)

      family_data = combined_results.group_by { |r| r["family_id"] }
                                    .transform_values do |records|

        records_with_dates = records.select { |r| r["submitted_at"].present? }
        if records_with_dates.any?
          records_with_dates.max_by { |r| r["submitted_at"] }
        else
          records.first
        end
      end

      family_ids = family_data.keys
      families = Family.where(:id.in => family_ids)
      Success(families)
    end

    def process_applicants(families)
      csv_data = collect_applicant_data(families)
      filepath = generate_csv_report(csv_data)

      Success("Processed hub calls and generated CSV report: #{filepath}")
    end

    def collect_applicant_data(families)
      csv_data = []

      families.each do |family|
        next unless family.latest_application.present?

        family.latest_application.applicants.each do |applicant|
          row_data = process_single_applicant(family, applicant)
          csv_data << row_data if row_data
        end
      end

      csv_data
    end

    def process_single_applicant(family, applicant)
      individual_market_eligibility = applicant.individual_market_eligibility
      evidences = get_relevant_evidences(individual_market_eligibility)
      eligible_evidences = filter_eligible_evidences(evidences)

      ssn_evidence = evidences.find { |e| e.key == "social_security_number_evidence" }
      citizenship_evidence = evidences.find { |e| e.key == "citizenship_evidence" }

      hub_call_made = make_hub_call_if_eligible(applicant, eligible_evidences)

      return nil unless hub_call_made

      build_csv_row(family, applicant, ssn_evidence, citizenship_evidence, hub_call_made)
    end

    def get_relevant_evidences(individual_market_eligibility)
      return [] unless individual_market_eligibility.present?
      individual_market_eligibility.evidences.select do |obj|
        ["social_security_number_evidence", "citizenship_evidence"].include?(obj.key)
      end
    end

    def filter_eligible_evidences(evidences)
      evidences.select do |evidence|
        evidence.verification_histories.present? && evidence.request_results.blank? && evidence.current_state == :pending
      end
    end

    def make_hub_call_if_eligible(applicant, eligible_evidences)
      return false unless eligible_evidences.present?

      Operations::Eligibilities::V3::IndividualMarket::SsaVlpVerification.new.call(
        {
          application: applicant.application,
          request_hbx_ids: [fetch_applicant_hbx_id(applicant)],
          call_type: 'hub_call',
          updated_by: 'admin action bulk hub call: CRM 28389'
        }
      )
      true
    end

    def build_csv_row(family, applicant, ssn_evidence, citizenship_evidence, hub_call_made)
      application = applicant.application

      [
        family.primary_person.hbx_id.to_s,
        application.hbx_id.to_s,
        application.assistance_year.to_s,
        application.submitted_at.to_s,
        fetch_applicant_hbx_id(applicant),
        ssn_evidence&.current_state || 'N/A',
        citizenship_evidence&.current_state || 'N/A',
        hub_call_made
      ]
    end

    def generate_csv_report(csv_data)
      csv_headers = ['Primary Person Hbx Id', 'Application ID', 'Application Assistance Year', 'Application Submitted At', 'Applicant HBX ID', 'SSN Evidence Status', 'Citizenship Evidence Status', 'Hub Call Made']

      timestamp = Time.current.strftime("%Y_%m_%d")
      filename = "hub_call_results_#{timestamp}.csv"
      filepath = Rails.root.join(filename)

      CSV.open(filepath, 'w') do |csv|
        csv << csv_headers
        csv_data.each { |row| csv << row }
      end

      Rails.logger.info "CSV report generated: #{filepath}"
      puts "CSV report generated: #{filepath}"

      filepath
    end

    def fetch_applicant_hbx_id(applicant)
      app_class = applicant.application.class
      if app_class == ::IndividualMarket::Application
        applicant.hbx_id
      elsif app_class == ::FinancialAssistance::Application
        applicant.person_hbx_id
      end
    end
  end
end