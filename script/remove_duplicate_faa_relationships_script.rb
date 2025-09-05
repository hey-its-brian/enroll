# frozen_string_literal: true

# This script takes a string of a year and initiates the operation to remove duplicate FAA relationships.

# Command to trigger the script:
# CLIENT=me bundle exec rails runner script/remove_duplicate_faa_relationships_script.rb '2025'

year = ARGV[0]

result = ::Operations::RemoveDuplicateFaaRelationships.new.call({ year: year })
if result.success?
  puts result.success
else
  puts result.failure
end
