require 'redis'
require 'json'

session_id = ENV["DETEST_SESSION_ID"]
redis_ip = ENV["DETEST_REDIS_IP"]
redis_password = ENV["DETEST_REDIS_PASSWORD"]

redis = Redis.new(host: redis_ip, password: redis_password)
members = redis.smembers("__#{session_id}_rspec_tp_adapter_test_results_storage")

member_list = []

members.each do |mem|
  member_data = JSON.parse(mem)
  member_list << member_data
end

sorted_data = member_list.sort_by do |item|
  item["duration"]
end

sorted_data[-10..-1].each do |sd|
  puts sd.inspect
end