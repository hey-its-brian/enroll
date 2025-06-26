# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::ContactProfile::SendSmsNotification, "with default settings and features" do
  it "does nothing" do
    expect(subject.call({}).success?).to be_truthy
  end
end

RSpec.describe Operations::ContactProfile::SendSmsNotification, "with the feature enabled" do
  let(:phone_number) { "443-555-5555" }
  let(:text_message) { "A NOTIFICATION MESSAGE" }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:enroll_sms_notifications).and_return(true)
  end

  context "and a phone number not on the blocklist" do
    it "publishes the message" do
      expect_any_instance_of(Aws::SNS::Client).to receive(:publish).with(
        {
          message: "A NOTIFICATION MESSAGE",
          phone_number: "4435555555"
        }
      )

      result = subject.call(
        {
          phone_number: phone_number,
          message: text_message
        }
      )

      expect(result.success?).to be_truthy
    end
  end

  context "and a phone number on the blocklist" do
    before :each do
      allow(::ContactProfile::PhoneBlocklist).to receive(:blocks?).with("4435555555").and_return(true)
    end

    it "does nothing" do
      expect(subject.call(
        {
          phone_number: phone_number,
          message: text_message
        }
      ).success?).to be_truthy
    end
  end
end