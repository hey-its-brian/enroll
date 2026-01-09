#frozen_string_literal: true

require File.join(Rails.root, "lib/mongoid_migration_task")

#Rake to update invalid counties in person addresses, Financial Assistance applicant addresses,
# and Individual marketplace applicant addresses based on zip code when they should be present
class UpdateMissingCounty < MongoidMigrationTask
  def migrate
    # Update Person addresses
    update_person_addresses

    # Update Financial Assistance applicant addresses
    update_financial_assistance_applicant_addresses

    # Update Individual marketplace applicant addresses
    update_individual_market_applicant_addresses
  end

  private

  def update_person_addresses
    people_with_invalid_county = Person.where(
      "addresses.county" => "Please provide a zip code",
      "addresses.zip" => { "$ne" => nil }
    )

    people_with_invalid_county.each do |person|
      person.addresses.each do |address|
        next if address.county != "Please provide a zip code" && address.zip.nil?
        county_zip = ::BenefitMarkets::Locations::CountyZip.where(:zip => address.zip, :state => address.state).last
        next unless county_zip&.county_name.present?
        address.county = county_zip.county_name
        address.save!
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
          next if address.county != "Please provide a zip code" && address.zip.nil?
          county_zip = ::BenefitMarkets::Locations::CountyZip.where(:zip => address.zip, :state => address.state).last
          next unless county_zip&.county_name.present?
          address.county = county_zip.county_name
          address.save!
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
          next if address.county != "Please provide a zip code" && address.zip.nil?
          county_zip = ::BenefitMarkets::Locations::CountyZip.where(:zip => address.zip, :state => address.state).last
          next unless county_zip&.county_name.present?
          address.county = county_zip.county_name
          address.save!
          puts "IM Application #{application.hbx_id} - Applicant #{applicant.hbx_id} - Address updated with county: #{county_zip.county_name}"
        end
      end
    end
  end
end