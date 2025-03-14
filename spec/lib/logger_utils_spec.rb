# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LoggerUtils do
  let(:test_class) do
    Class.new do
      include LoggerUtils
    end
  end

  let(:test_instance) { test_class.new }
  let(:rails_logger) { double('Rails.logger') }

  before do
    allow(Rails).to receive(:logger).and_return(rails_logger)
    allow(rails_logger).to receive(:info)
    allow(rails_logger).to receive(:error)
    allow(rails_logger).to receive(:debug)
  end

  describe '#find_caller_info' do
    it 'returns a hash with immediate and originating caller info' do
      result = test_instance.find_caller_info
      expect(result).to be_a(Hash)
      expect(result.keys).to match_array([:immediate, :originating])
    end

    it 'filters out excluded files' do
      allow(test_instance).to receive(:caller).and_return([
        "/app/models/file1.rb:10:in `some_method'",
        "/app/models/excluded.rb:20:in `excluded_method'",
        "/app/models/file2.rb:30:in `another_method'"
      ])

      result = test_instance.find_caller_info(['excluded.rb'])
      expect(result[:immediate]).to eq("/app/models/file1.rb:10:in `some_method'")
      expect(result[:originating]).to eq("/app/models/file2.rb:30:in `another_method'")
    end
  end

  describe '#extract_caller_identity' do
    it 'returns "Unknown caller" for nil input' do
      expect(test_instance.extract_caller_identity(nil)).to eq("Unknown caller")
    end

    it 'returns "Unknown caller" for input that does not match the pattern' do
      expect(test_instance.extract_caller_identity("some random string")).to eq("Unknown caller")
    end

    it 'extracts class path and method name correctly' do
      caller_entry = "/app/models/some_model.rb:45:in `do_something'"
      expect(test_instance.extract_caller_identity(caller_entry)).to eq("some_model#do_something")
    end
  end

  describe '#log' do
    before do
      allow(test_instance).to receive(:caller).and_return([
        "/app/controllers/users_controller.rb:45:in `show'",
        "/app/lib/some_helper.rb:20:in `process_data'",
        "/app/models/user.rb:15:in `find_by_name'"
      ])
      allow(test_class).to receive(:name).and_return("TestClass")
    end

    it 'logs a message with caller information' do
      expect(rails_logger).to receive(:info).with("test message | immediate caller: users_controller#show | originating caller: user#find_by_name")

      test_instance.log("test message")
    end

    it 'logs at the specified level' do
      expect(rails_logger).to receive(:error).with(anything)

      test_instance.log("error message", level: :error)
    end

    it 'handles errors gracefully' do
      allow(rails_logger).to receive(:info).and_raise(StandardError.new("Test error"))
      expect(rails_logger).to receive(:error).with("Error while logging: Test error")

      test_instance.log("problematic message")
    end
  end

  describe 'specialized logging methods' do
    before do
      allow(test_instance).to receive(:log)
    end

    it '#log_info calls #log with :info level' do
      expect(test_instance).to receive(:log).with("info message", level: :info)
      test_instance.log_info("info message")
    end

    it '#log_error calls #log with :error level' do
      expect(test_instance).to receive(:log).with("error message", level: :error)
      test_instance.log_error("error message")
    end

    it '#log_debug calls #log with :debug level' do
      expect(test_instance).to receive(:log).with("debug message", level: :debug)
      test_instance.log_debug("debug message")
    end
  end
end