# frozen_string_literal: true

# This script initiates the operation to call Hub for applicants with no SSN and US citizen status.

# Command to trigger the script:
# CLIENT=me bundle exec rails runner script/call_hub_for_applicants_with_no_ssn_and_citizen_status.rb


result = Operations::CallHubForNoSsnUsCitizenApplicants.new.call
puts result.success