# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::ContactProfile::SendSmsNotification, "with default settings and features" do
  it "does nothing" do
    expect(subject.call({}).success?).to be_truthy
  end
end

RSpec.describe Operations::ContactProfile::SendSmsNotification, "with the feature enabled and given a phone number" do
  let(:phone_number) { "443-555-5555" }
  let(:text_message) { "A NOTIFICATION MESSAGE" }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:enroll_sms_notifications).and_return(true)
  end

  it "publishes the message" do
    result = subject.call(
      {
        phone_number: phone_number,
        message: text_message
      }
    )

    expect(result.success?).to be_truthy
  end
end