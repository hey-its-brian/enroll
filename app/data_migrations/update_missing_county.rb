#frozen_string_literal: true

require File.join(Rails.root, "lib/mongoid_migration_task")
require 'csv'

#Rake to update invalid counties in person addresses, Financial Assistance applicant addresses,
# and Individual marketplace applicant addresses based on zip code when they should be present
class UpdateMissingCounty < MongoidMigrationTask
  def migrate
    @csv_file = "update_missing_county_#{Time.now.strftime('%Y%m%d_%H%M%S')}.csv"

    CSV.open(@csv_file, 'w', headers: true) do |csv|
      csv << ['Record Type', 'Application HBX ID', 'Person HBX ID', 'Address Type', 'Old County', 'New County', 'Zip Code', 'State', 'Updated At']
      @csv = csv

      # Update Person addresses
      update_person_addresses

      # Update Financial Assistance applicant addresses
      update_financial_assistance_applicant_addresses

      # Update Individual marketplace applicant addresses
      update_individual_market_applicant_addresses
    end

    puts "CSV log file created: #{@csv_file}"
  end

  private

  def update_person_addresses
    people_with_invalid_county = Person.where(
      "addresses.county" => "Please provide a zip code",
      "addresses.zip" => { "$ne" => nil },
      "addresses.state" => "ME"
    )

    people_with_invalid_county.each do |person|
      person.addresses.each do |address|
        next if address.county != "Please provide a zip code" || address.zip.nil?
        county_zip = ::BenefitMarkets::Locations::CountyZip.where(:zip => address.zip, :state => address.state).last
        next unless county_zip&.county_name.present?

        old_county = address.county
        address.county = county_zip.county_name
        address.save!

        @csv << ['Person', 'N/A', person.hbx_id, address.kind, old_county, county_zip.county_name, address.zip, address.state, Time.now]
        puts "Person #{person.hbx_id} - Address updated with county: #{county_zip.county_name}"
      end
    end
  end

  def update_financial_assistance_applicant_addresses
    fa_applications_with_invalid_county = ::FinancialAssistance::Application.where(
      "applicants.addresses.county" => "Please provide a zip code",
      "applicants.addresses.zip" => { "$ne" => nil },
      :assistance_year.in => [2025, 2026],
      :aasm_state.ne => "determined"
    )

    fa_applications_with_invalid_county.each do |application|
      application.applicants.each do |applicant|
        applicant.addresses.each do |address|
          next if address.county != "Please provide a zip code" || address.zip.nil?
          county_zip = ::BenefitMarkets::Locations::CountyZip.where(:zip => address.zip, :state => address.state).last
          next unless county_zip&.county_name.present?

          old_county = address.county
          address.county = county_zip.county_name
          address.save!

          @csv << ['FA Application', application.hbx_id, applicant.person_hbx_id, address.kind, old_county, county_zip.county_name, address.zip, address.state, Time.now]
          puts "FA Application #{application.hbx_id} - Applicant #{applicant.person_hbx_id} - Address updated with county: #{county_zip.county_name}"
        end
      end
    end
  end

  def update_individual_market_applicant_addresses
    im_applications_with_invalid_county = ::IndividualMarket::Application.where(
      "applicants.addresses.county" => "Please provide a zip code",
      "applicants.addresses.zip" => { "$ne" => nil },
      :assistance_year.in => [2025, 2026],
      :current_state.ne => :determined
    )

    im_applications_with_invalid_county.each do |application|
      application.applicants.each do |applicant|
        applicant.addresses.each do |address|
          next if address.county != "Please provide a zip code" || address.zip.nil?
          county_zip = ::BenefitMarkets::Locations::CountyZip.where(:zip => address.zip, :state => address.state).last
          next unless county_zip&.county_name.present?

          old_county = address.county
          address.county = county_zip.county_name
          address.save!

          @csv << ['IM Application', application.hbx_id, applicant.hbx_id, address.kind, old_county, county_zip.county_name, address.zip, address.state, Time.now]
          puts "IM Application #{application.hbx_id} - Applicant #{applicant.hbx_id} - Address updated with county: #{county_zip.county_name}"
        end
      end
    end
  end
end