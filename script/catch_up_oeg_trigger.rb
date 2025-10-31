# frozen_string_literal: true

# Trigger OEG notices for missing families
# Option1: rails runner script/catch_up_oeg_trigger.rb "2025-10-23" "" "retrigger_for_all_non_determined_applications" 2026
# Option2: rails runner script/catch_up_oeg_trigger.rb "2025-10-23" "12345,67890" "" 2026

from_date = ARGV[0]&.to_date
primary_person_hbx_ids_list = ARGV[1]&.split(",") || []
retrigger_for_all_non_determined_applications = ARGV[2]&.strip == 'retrigger_for_all_non_determined_applications'
renewal_year = ARGV[3]&.to_i

unless from_date
  puts "Must provide from_date in 'YYYY-MM-DD' or 'YYYY/MM/DD' format. Provided: #{ARGV[0]}"
  exit 1
end

start_time = DateTime.current
puts "oeg_catch_up_notice_triggers start_time: #{start_time}"

primary_person_hbx_ids = if retrigger_for_all_non_determined_applications
                           family_ids  = if EnrollRegistry.feature_enabled?(:oeg_notice_income_verification_only)
                                           ::FinancialAssistance::Application.by_year(renewal_year).income_verification_extension_required.distinct(:family_id)
                                         else
                                           ::FinancialAssistance::Application.by_year(renewal_year).non_determined.distinct(:family_id)
                                         end

                           Family.where(:id.in => family_ids).map(&:primary_person).flatten.map(&:hbx_id)
                         else
                           primary_person_hbx_ids_list
                         end

unless primary_person_hbx_ids.present?
  puts "No primary_person_hbx_ids found to process."
  exit 1
end

primary_person_hbx_ids.each do |primary_person_hbx_id|
  person = Person.by_hbx_id(primary_person_hbx_id).first
  family = person.primary_family
  app = FinancialAssistance::Application.where(family_id: family.id, :predecessor_id.ne => nil).by_year(renewal_year).non_determined.max_by(&:created_at)

  if family.present? && app.present?
    oeg_notices = person.documents.where(title: "Your Eligibility Results Consent or Missing Information Needed", :created_at.gte => from_date)

    if oeg_notices.present?
      puts "#{person.hbx_id} | #{oeg_notices.present?} | #{oeg_notices.count} | Already sent notices, skipping..."
    else
      result = ::Operations::Notices::IvlOeReverificationTrigger.new.call({ family: family, notice_type: 'oeg' })
      if result.success?
        puts "Successfully triggered OEG notice for person HBX ID: #{person.hbx_id}"
      else
        puts "Failed to trigger OEG notice for person HBX ID: #{person.hbx_id}, Error: #{result.failure}"
      end
    end
  else
    puts "no primary family for the given person or no non_determined application for person HBX ID: #{primary_person_hbx_id}"
  end
rescue StandardError => e
  puts "Error processing person HBX ID: #{primary_person_hbx_id}, Error: #{e.message}"
end

end_time = DateTime.current
puts "oeg_catch_up_notice_triggers end_time: #{end_time}, total_time_taken_in_minutes: #{((end_time - start_time) * 24 * 60).to_f.ceil}"
