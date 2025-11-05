# frozen_string_literal: true

# This script generates a CSV report listing Person records
# with addresses missing or mismatched county and zip codes.
#
# Usage:
#   bundle exec rails runner script/export_invalid_person_addresses.rb
#
# The generated CSV file will be saved to tmp/invalid_person_addresses_TIMESTAMP.csv

require 'csv'
require 'set'

valid_pairs = ::BenefitMarkets::Locations::CountyZip.pluck(:county_name, :zip).map do |county, zip|
  [county.to_s.downcase.strip, zip.to_s.strip]
end.to_set

timestamp = Time.now.strftime("%Y%m%d%H%M%S")
file_path = Rails.root.join("tmp", "invalid_person_addresses_#{timestamp}.csv")

CSV.open(file_path, "w+", headers: true) do |csv|
  csv << ["person_hbx_id", "address_zip", "address_kind", "address_county", "address_created_at", "reason"]

  batch_size = 10_000
  total_count = Person.count
  number_of_batches = (total_count / batch_size.to_f).ceil

  number_of_batches.times do |batch_index|
    offset = batch_index * batch_size
    batch = Person.skip(offset).limit(batch_size)
    batch.each do |person|
      next if person.addresses.blank?

      # Will export one row per invalid address (could be multiple per person)
      person.addresses.each do |address|
        if address.county.blank? || address.zip.blank?
          csv << [
            person.hbx_id,
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
              person.hbx_id,
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

puts "Person address audit CSV created at: #{file_path}"
