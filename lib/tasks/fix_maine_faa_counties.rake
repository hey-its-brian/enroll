# Migration for fixing nil maine counties
require File.join(Rails.root, "app", "helpers", "me_county_helper")
include MeCountyHelper

namespace :migrations do
  desc "Fix Mil Maine Counties"
  # Run this with RAILS_ENV=production bundle exec rake migrations:fix_maine_faa_counties
  task :fix_maine_faa_counties, [:file] => :environment do |task, args|
    impacted_application_ids = find_impacted_application_ids
    failures = []
    process_impacted_applications(impacted_application_ids) do |address|
      result = fix_address(address)
      failures << [
        address.applicant.application.family.primary_applicant.person.hbx_id,
        address.applicant.application.hbx_id,
        address.zip,
        address.city,
        address.county,
        address.state
      ] unless result
    end
    write_csv("county_fix_failures", ["Family HBX ID", "Application HBX ID", "ZIP", "City", "County", "State"], failures) if failures.present?
  end

  # Run this with RAILS_ENV=production bundle exec rake migrations:generate_impact_list
  task :generate_impact_list, [:file] => :environment do |task, args|
    impacted_application_ids = find_impacted_application_ids
    impacts = []
    process_impacted_applications(impacted_application_ids) do |address|
      impacts << [
        address.applicant.application.family.primary_applicant.person.hbx_id,
        address.applicant.application.hbx_id,
        address.zip,
        address.city,
        address.county,
        address.state
      ]
    end
    write_csv("county_fix_impacts", ["Family HBX ID", "Application HBX ID", "ZIP", "City", "County", "State"], impacts)
  end

  def address_county_valid?(address)
    valid = address.valid?
    return true if valid
    return address.errors.errors.map(&:type).none? { |type| type == 'invalid county/zip' }
  end

  def find_impacted_application_ids
    batch_size = 1000
    count = 0
    offset = 0
    total_count = FinancialAssistance::Application.determined.where(:assistance_year.in => [2024, 2025]).count
    puts "Processing #{total_count} applications in #{total_count.to_f / batch_size} batches of #{batch_size}"
    impacted_applications = []
    loop do
      batch = FinancialAssistance::Application.determined.where(:assistance_year.in => [2024, 2025])
              .skip(offset)
              .limit(batch_size)
              .to_a
      
      break if batch.empty?
      
      batch.each do |app|
        count += 1
        puts "Processed #{count} applications of #{total_count}" if count % 1000 == 0
        
        impacted_addresses = app.applicants.map(&:addresses).flatten.select { |address| !address_county_valid?(address) }
        impacted_applications << app.hbx_id if impacted_addresses.any?
      end

      offset += batch_size

      GC.start
    end
    impacted_applications
  end

  def fix_address(address)
    counties_by_zip = counties_by_zip(address.zip)
    county_by_city = county_by_city(address.city)
    if counties_by_zip.present?
      if counties_by_zip.count == 1
        address.county = counties_by_zip.first.county_name
        address.save
      elsif county_by_city.present?
        address.county = county_by_city
        address.save
      end
    end
  end

  def counties_by_zip(zip)
    ::BenefitMarkets::Locations::CountyZip.where(zip: zip)
  end

  def county_by_city(city)
    maine_counties_and_towns.detect { |key, _value| maine_counties_and_towns[key].include?(city) }&.first
  end

  def process_impacted_applications(application_ids, &block)
    count = 0
    
    application_ids.each do |hbx_id|
      puts "Processing application #{count}" if count % 100 == 0
      count += 1
      
      app = FinancialAssistance::Application.find_by(hbx_id: hbx_id)
      raise "Application withmp hbx_id #{hbx_id} not found" unless app

      impacted_addresses = app.applicants.map(&:addresses).flatten.select { |address| !address_county_valid?(address) }
      raise "No impacted addresses found for application #{hbx_id}" if impacted_addresses.empty?

      impacted_addresses.each { |address| block.call(address) }
    end
  end

  def write_csv(file, headers, data)
    file_name = "#{file}.csv"
    file_path = Rails.root.join('tmp', file_name)
    CSV.open(file_path, 'w') do |csv|
      csv << headers
      data.each do |row|
        formatted_row = row.map.with_index do |cell, index|
          if index == 2 && cell.is_a?(String) # ZIP column
            "=\"#{cell}\""
          else
            cell
          end
        end
        csv << formatted_row
      end
    end
    puts "Report file generated at: #{file_path}"
  end
end
