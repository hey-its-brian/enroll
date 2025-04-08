# frozen_string_literal: true

# script to correct demographic information for consumers
# bundle exec rails runner script/trigger_consumer_demographic_information_update.rb

start_time = Time.now
puts "** Start time: #{start_time} **"
file_path = "#{Rails.root}/consumers_needing_updates.csv"
result = ::Operations::UpdateConsumerDemographicInformation.new.call(file_path: file_path)

result.success? ? puts("Success: #{result.success}") : puts("Failure: #{result.failure}")

end_time = Time.now

puts "** End time: #{end_time} **"