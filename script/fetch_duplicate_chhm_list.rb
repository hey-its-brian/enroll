# frozen_string_literal: true

# This script generates a CSV report with information about families with duplicate coverage household members.
# To run this 
# bundle exec rails runner script/fetch_duplicate_chhm_list.rb

require 'csv'

date = Time.now.strftime("%Y%m%d_%H%M%S")
CSV.open("#{Rails.root}/script_to_fetch_invalid_coverage_household_members_#{date}.csv", "w", force_quotes: true) do |csv|
  csv << [
    'Primary Person Hbx Id',
    'Coverage Household Created At',
    'Coverage Household Member Created At',
    'Reason'
  ]
  
  duplicates = Family.collection.aggregate([
    { "$match" => { "households" => { "$exists" => true } } },
    { "$unwind" => "$households" },
    { "$match" => { "households.is_active" => true } },
    { "$unwind" => "$households.coverage_households" },
    { "$unwind" => "$households.coverage_households.coverage_household_members" },
    {
      "$group" => {
        "_id" => {
          family_id: "$_id",
          coverage_household_id: "$households.coverage_households._id",
          family_member_id: "$households.coverage_households.coverage_household_members.family_member_id"
        },
        "count" => { "$sum" => 1 }
      }
    },
    { "$match" => { "count" => { "$gt" => 1 } } },
    { "$group" => { "_id" => "$_id.family_id" } }
  ])

  family_ids = duplicates.map { |doc| doc["_id"] }
  families = Family.where(:_id.in => family_ids)
  
  families.each do |family|
    begin
      active_household = family.active_household
      next if active_household.nil?
      
      coverage_households = active_household.coverage_households
      next if coverage_households.nil? || coverage_households.empty?
    
      coverage_households.each do |coverage_household|
        grouped = coverage_household.coverage_household_members
                          .reject { |chm| chm.family_member.nil? }
                          .group_by(&:family_member_id)

        grouped.each do |family_member_id, members|
          if members.size > 1
            members.sort_by(&:created_at)[1..].each do |duplicate_chm|
              csv << [
                family.primary_person.hbx_id,
                coverage_household.created_at,
                duplicate_chm.created_at,
                "Duplicate CHM for family_member_id #{family_member_id}"
              ]
            end
          end
        end
      end

    rescue StandardError => e
      puts "Error processing family #{family.primary_person&.hbx_id}: #{e.message}"
      puts e.backtrace.join("\n")
    end
  end
end