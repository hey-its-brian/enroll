# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::People::HandleInboxMessageReceived, "given person id for someone without a consumer role" do
  let(:person_id) { "A PERSON ID" }
  let(:person) do
    instance_double(Person, consumer_role: nil)
  end

  before :each do
    allow(Person).to receive(:where).with({_id: person_id}).and_return([person])
  end

  it "does nothing" do
    expect(described_class.new.call({person_id: "A PERSON ID"}).success?).to be_truthy
  end
end

RSpec.describe Operations::People::HandleInboxMessageReceived, "given a person id for someone with a consumer role, who can't receive texts" do
  let(:person_id) { "A PERSON ID" }
  let(:person) do
    instance_double(Person, consumer_role: consumer_role)
  end
  let(:consumer_role) { instance_double(ConsumerRole, :can_receive_text_communication? => false)}

  before :each do
    allow(Person).to receive(:where).with({_id: person_id}).and_return([person])
  end

  it "does nothing" do
    expect(described_class.new.call({person_id: "A PERSON ID"}).success?).to be_truthy
  end
end

RSpec.describe Operations::People::HandleInboxMessageReceived, "given a person id for someone with a consumer role, who can receive texts" do
  include Dry::Monads[:result]

  let(:person_id) { "A PERSON ID" }
  let(:person) do
    instance_double(Person, consumer_role: consumer_role)
  end
  let(:consumer_role) { instance_double(ConsumerRole, :can_receive_text_communication? => true, :mobile_phone => phone_number)}
  let(:mock_send_operation) { double }
  let(:phone_number) { "410-555-5555" }

  before :each do
    allow(Person).to receive(:where).with({_id: person_id}).and_return([person])
    allow(::Operations::ContactProfile::SendSmsNotification).to receive(:new).and_return(mock_send_operation)
  end

  it "sends the SMS message" do
    expect(mock_send_operation).to receive(:call).with(
      {
        :phone_number => phone_number,
        :message => EnrollRegistry[:enroll_sms_notifications].setting(:sms_inbox_notification_text)&.item
      }
    ).and_return(Success(:ok))

    expect(described_class.new.call({person_id: "A PERSON ID"}).success?).to be_truthy
  end
end