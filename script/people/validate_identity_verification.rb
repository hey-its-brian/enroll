# frozen_string_literal: true

# Script to run identity verification index updates
# will update the identity verification index for users based on their identity response code.
# Usage:
#   bundle exec rails runner script/people/validate_identity_verification.rb report acc
#   bundle exec rails runner script/people/validate_identity_verification.rb update_identity_verification acc
#
# First argument: type (report or update_identity_verification)
# Second argument: identity_response_code to filter by

type = ARGV[0] || 'report'
identity_response_code = ARGV[1] || 'acc'

puts "Running identity verification index update:"
puts "  Type: #{type}"
puts "  Identity Response Code: #{identity_response_code}"

params = {
  type: type,
  identity_response_code: identity_response_code
}

result = Operations::People::ValidateIdentityVerification.new.call(params)

if result.success?
  puts "Success: #{result.value!}"

  if type == 'report'
    puts "Report generated: user_identity_validation_report.csv"
  else
    puts "Identity verification updated for users with identity_response_code: #{identity_response_code}"
  end
else
  puts "Error: #{result.failure}"
end