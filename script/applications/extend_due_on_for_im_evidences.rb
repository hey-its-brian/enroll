# frozen_string_literal: true
#
# Script: 
# Extend individual market evidence due dates for targeted applicants
# Takes a string of the start date and extension days as CLI arguments, finds relevant applicants, and extends due dates for evidences in eligible states.

# Usage:
#   bundle exec rails runner script/applications/extend_due_on_for_im_evidences.rb "2025/10/16" "96"

start_on = ARGV[0].strip
days = ARGV[1].to_i

result = Operations::Eligibilities::ExtendDueDateForImEvidences.new.call(
  start_date: start_on,
  extension_days: days
)

puts result.success? ? "Success: #{result.value!}" : "Failure: #{result.failure}"
