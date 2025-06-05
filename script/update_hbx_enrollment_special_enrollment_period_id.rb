# frozen_string_literal: true

# This script takes a string of a year and initiates the operation to update hbx enrollment special enrollment period IDs.

# Command to trigger the script:
# CLIENT=me bundle exec rails runner script/update_hbx_enrollment_special_enrollment_period_id.rb '2025'

year = ARGV[0]

result = ::Operations::UpdateHbxEnrollmentSpecialEnrollmentPeriodId.new.call({ year: year })
if result.success?
  puts result.success
else
  puts result.failure
end
