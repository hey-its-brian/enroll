# frozen_string_literal: true

# This script generates a CSV report listing Financial Assistance applicants
# whose addresses have missing or mismatched county and zip codes.
#
# Usage:
#   bundle exec rails runner script/export_invalid_county_zip_for_applicants.rb
#
# The generated CSV file will be saved to tmp/invalid_county_zip_report_TIMESTAMP.csv


require 'csv'
require 'set'

valid_pairs = ::BenefitMarkets::Locations::CountyZip.pluck(:county_name, :zip).map do |county, zip|
  [county.to_s.downcase.strip, zip.to_s.strip]
end.to_set

timestamp = Time.now.strftime("%Y%m%d%H%M%S")
file_path = Rails.root.join("tmp", "invalid_county_zip_report_#{timestamp}.csv")

CSV.open(file_path, "w+", headers: true) do |csv|
  csv << ["person_hbx_id", "application_hbx_id", "assistance_year", "application_aasm_state", "address_zip", "address_kind", "address_county", "address_created_at", "reason"]

  batch_size = 10_000
  applications = ::FinancialAssistance::Application.all
  total_count = applications.count
  number_of_batches = (total_count / batch_size.to_f).ceil

  number_of_batches.times do |batch_index|
    offset = batch_index * batch_size
    batch = applications.skip(offset).limit(batch_size)
    batch.each do |application|
      next unless application.applicants.present?

      application.applicants.each do |applicant|
        next if applicant.addresses.blank?

        applicant.addresses.each do |address|
          if address.county.blank? || address.zip.blank?
            csv << [
              application&.primary_applicant&.person_hbx_id,
              application&.hbx_id,
              application&.assistance_year,
              application&.aasm_state,
              address.zip,
              address.kind,
              address.county,
              address.created_at,
              "Missing ZIP or County"
            ]
          else
            pair = [address.county.to_s.downcase.strip, address.zip.to_s.strip]
            unless valid_pairs.include?(pair)
              csv << [
                application&.primary_applicant&.person_hbx_id,
                application&.hbx_id,
                application&.assistance_year,
                application&.aasm_state,
                address.zip,
                address.kind,
                address.county,
                address.created_at,
                "County–ZIP mismatch"
              ]
            end
          end
        end
      end
    end
  end
end

puts "CSV file generated at: #{file_path}"
