# frozen_string_literal: true

# Trigger OEG notices for missing families
# Option1: rails runner script/catch_up_oeq_trigger.rb "2025-10-23" "" "retrigger_for_all_qhp_application" 2026
# Option2: rails runner script/catch_up_oeq_trigger.rb "2025-10-23" "12345,67890" "" 2026

from_date = ARGV[0]&.to_date
primary_person_hbx_ids_list = ARGV[1]&.split(",") || []
retrigger_for_all_qhp_application = ARGV[2]&.strip == 'retrigger_for_all_qhp_application'
renewal_year = ARGV[3]&.to_i

unless from_date
  puts "Must provide from_date in 'YYYY-MM-DD' or 'YYYY/MM/DD' format. Provided: #{ARGV[0]}"
  exit 1
end

start_time = DateTime.current
puts "oeq_catch_up_notice_triggers start_time: #{start_time}"

primary_person_hbx_ids = if retrigger_for_all_qhp_application
                           family_ids = ::IndividualMarket::Application.where(
                             current_state: :determined,
                             assistance_year: renewal_year,
                             :'applicants.eligibilities' => {
                               :$elemMatch => {
                                 :'determinations._type' => 'Eligibilities::V3::Determinations::IndividualMarketDetermination',
                                 :'determinations.is_eligible' => true
                               }
                             }
                           ).distinct(:family_id)

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

   app = ::IndividualMarket::Application.where(
                             current_state: :determined,
                             family_id: family.id,
                             assistance_year: renewal_year,
                             :'applicants.eligibilities' => {
                               :$elemMatch => {
                                 :'determinations._type' => 'Eligibilities::V3::Determinations::IndividualMarketDetermination',
                                 :'determinations.is_eligible' => true
                               }
                             }
                           ).first

  if family.present? && app.present?
    oeq_notices = person.documents.where(title: "Your Eligibility Results - Health Coverage Eligibility", :created_at.gte => from_date)

    if oeq_notices.present?
      puts "#{person.hbx_id} | #{oeq_notices.present?} | #{oeq_notices.count} | Already sent notices, skipping..."
    else
      result = ::Operations::Notices::IvlOeReverificationTrigger.new.call({ family: family, notice_type: 'oeq' })
      if result.success?
        puts "Successfully triggered OEQ notice for person HBX ID: #{person.hbx_id}"
      else
        puts "Failed to trigger OEQ notice for person HBX ID: #{person.hbx_id}, Error: #{result.failure}"
      end
    end
  else
    puts "no primary family for the given person or valid QHP is present"
  end
end

end_time = DateTime.current
puts "#{notice_type}_catch_up_notice_triggers end_time: #{end_time}, total_time_taken_in_minutes: #{((end_time - start_time) * 24 * 60).to_f.ceil}"
