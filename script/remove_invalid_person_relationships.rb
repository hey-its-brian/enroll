# frozen_string_literal: true


# Command to trigger the script:
# CLIENT=me bundle exec rails runner script/remove_invalid_person_relationships.rb

result = ::Operations::RemoveInvalidPersonRelationships.new.call({})
puts result.success if result.success?