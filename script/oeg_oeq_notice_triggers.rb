# frozen_string_literal: true

# Trigger OEQ & OEG notices (to be done post-renewals)
# rails runner script/oeg_oeq_notice_triggers.rb oeg|oeq|oeg_oeq

notice_type = ARGV[0]&.downcase

unless notice_type
  puts "Must provide (oeg || oeq || oeg_oeq) enrollment type provided: #{ARGV[0]}"
  exit 1
end

start_time = DateTime.current
puts "#{notice_type}_notice_triggers start_time: #{start_time}"

result = Operations::HbxEnrollments::DetermineOeNoticeRecipients.new.call(notice_type: notice_type)

if result.success?
  puts "Successfully processed #{notice_type} notices."
else
  puts "Failed to process #{notice_type} notices: #{result.failure}"
end

end_time = DateTime.current
puts "#{notice_type}_notice_triggers end_time: #{end_time}, total_time_taken_in_minutes: #{((end_time - start_time) * 24 * 60).to_f.ceil}"
