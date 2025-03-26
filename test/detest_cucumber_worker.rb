require 'detest'

session_id = ENV["DETEST_SESSION_ID"]
redis_ip = ENV["DETEST_REDIS_IP"]
redis_password = ENV["DETEST_REDIS_PASSWORD"]

adapter = Detest::Adapters::RedisAdapter.new(session_id + "_cucumber", host: redis_ip, password: redis_password)
Detest::Workers::CucumberWorker.run!(adapter, ARGV)