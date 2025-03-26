require 'detest'

session_id = ENV["DETEST_SESSION_ID"]
redis_ip = ENV["DETEST_REDIS_IP"]
redis_password = ENV["DETEST_REDIS_PASSWORD"]

adapter = Detest::Adapters::RedisAdapter.new(session_id + "_rspec", host: redis_ip, password: redis_password)

client = Detest::Workers::RspecWorker.boot(ARGV)
client.run(adapter)