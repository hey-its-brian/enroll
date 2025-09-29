# frozen_string_literal: true

require 'rails_helper'

# Helper functions for Opt out testing
module HandleSmsOptOutScenarioHelper
  def self.included(base)
    base.class_exec do
      include Dry::Monads[:result]

      after :each do
        Person.where({}).delete
      end

      let(:lookup_operation) do
        instance_double(
          Operations::ContactProfile::FindConsumersBySmsNumber
        )
      end

      let(:found_records) do
        Success([person])
      end

      before :each do
        allow(EnrollRegistry).to receive(:feature_enabled?).with(:enroll_sms_notifications).and_return(true)
        allow(Operations::ContactProfile::FindConsumersBySmsNumber).to receive(:new).and_return(lookup_operation)
        allow(lookup_operation).to receive(:call).with(phone_number).and_return(found_records)
      end

      let(:phone_number) { "4435551234" }

      let(:logger) { double }

      let(:params) do
        {
          :phone => phone_number,
          :logger => logger
        }
      end

      let(:subject) { described_class.new }

      let(:result) { subject.call(params) }
    end
  end
end

RSpec.describe Operations::ContactProfile::HandleSmsOptOutNotification, "given a phone number with a matching consumer who has email and mail" do
  include HandleSmsOptOutScenarioHelper

  let(:person) do
    pers = FactoryBot.create(:person, :with_consumer_role)
    pers.consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Email", "Mail", "Text"]]
    pers.phones[0].kind = 'mobile'
    pers.save!
    pers
  end

  it "updates the contact preferences to be email and mail" do
    expect(result.success?).to be_truthy
    person.reload
    expect(person.consumer_role.current_contact_methods).to eq ["Email", "Mail"]
  end
end

RSpec.describe Operations::ContactProfile::HandleSmsOptOutNotification, "given a phone number with a matching consumer who has email" do
  include HandleSmsOptOutScenarioHelper

  let(:person) do
    pers = FactoryBot.create(:person, :with_consumer_role)
    pers.consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Email", "Text"]]
    pers.phones[0].kind = 'mobile'
    pers.addresses = []
    pers.save!
    pers
  end

  it "updates the contact preferences to be email" do
    expect(result.success?).to be_truthy
    person.reload
    expect(person.consumer_role.current_contact_methods).to eq ["Email"]
  end

end

RSpec.describe Operations::ContactProfile::HandleSmsOptOutNotification, "given a phone number with a matching consumer who has mail" do
  include HandleSmsOptOutScenarioHelper

  let(:person) do
    pers = FactoryBot.create(:person, :with_consumer_role)
    pers.consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Mail", "Text"]]
    pers.phones[0].kind = 'mobile'
    pers.emails = []
    pers.save!
    pers
  end

  it "updates the contact preferences to be Mail" do
    expect(result.success?).to be_truthy
    person.reload
    expect(person.consumer_role.current_contact_methods).to eq ["Mail"]
  end

end

RSpec.describe Operations::ContactProfile::HandleSmsOptOutNotification, "given a phone number with a matching consumer who has only text selected, but has an email" do
  include HandleSmsOptOutScenarioHelper

  let(:person) do
    pers = FactoryBot.create(:person, :with_consumer_role)
    pers.consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Text"]]
    pers.phones[0].kind = 'mobile'
    pers.addresses = []
    pers.save!
    pers.reload
    pers
  end

  it "updates the contact preferences to be email" do
    expect(result.success?).to be_truthy
    person.reload
    expect(person.consumer_role.current_contact_methods).to eq ["Email"]
  end

end

RSpec.describe Operations::ContactProfile::HandleSmsOptOutNotification, "given a phone number with a matching consumer who has only text selected, but has an address" do
  include HandleSmsOptOutScenarioHelper

  let(:person) do
    pers = FactoryBot.create(:person, :with_consumer_role)
    pers.consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Text"]]
    pers.phones[0].kind = 'mobile'
    pers.emails = []
    pers.save!
    pers.reload
    pers
  end

  it "updates the contact preferences to be mail" do
    expect(result.success?).to be_truthy
    person.reload
    expect(person.consumer_role.current_contact_methods).to eq ["Mail"]
  end
end

RSpec.describe Operations::ContactProfile::HandleSmsOptOutNotification, "given a phone number with a matching consumer who has only text selected, but and no email or address" do
  include HandleSmsOptOutScenarioHelper

  let(:person) do
    pers = FactoryBot.create(:person, :with_consumer_role)
    pers.consumer_role.contact_method = ConsumerRole::CONTACT_METHOD_MAPPING[["Text"]]
    pers.phones[0].kind = 'mobile'
    pers.addresses = []
    pers.emails = []
    pers.save!
    pers.reload
    pers
  end

  it "logs an error" do
    expect(logger).to receive(:error).with("Matched individual #{person.id} has no other available methods of contact, not opting out.")
    expect(result.success?).to be_truthy
    person.reload
    expect(person.consumer_role.current_contact_methods).to eq ["Text"]
  end
end