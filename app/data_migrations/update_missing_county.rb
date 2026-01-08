#frozen_string_literal: true

require File.join(Rails.root, "lib/mongoid_migration_task")

#Rake to update invalid counties in person addresses based on zip code when they should be present
class UpdateMissingCounty < MongoidMigrationTask
  def migrate
    people_with_invalid_county = Person.where(
      "addresses.county" => "Please provide a zip code",
      "addresses.zip" => { "$ne" => nil }
    )

    people_with_invalid_county.each do |person|
      person.addresses.each do |address|
        next if address.county != "Please provide a zip code" && address.zip.nil?
        county_zip = ::BenefitMarkets::Locations::CountyZip.where(:zip => address.zip, :state => address.state).last
        if county_zip&.county_name.present?
          address.county = county_zip.county_name
          address.save!
          puts "Person #{person.hbx_id} - Address updated with county: #{county_zip.county_name}"
        else
          puts "Person #{person.hbx_id} - No county found for zip: #{address.zip}, state: #{address.state}"
        end
      end
    end
  end
end