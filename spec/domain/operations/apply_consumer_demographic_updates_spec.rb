# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Operations::ApplyConsumerDemographicUpdates, type: :model, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }

  let(:update_data) do
    {
      person: person,
      consumer_role: person.consumer_role,
      mailing_address: person.addresses.where(kind: 'mailing').first,
      home_address: person.addresses.where(kind: 'home').first,
      home_email_address: person.emails.where(kind: 'home').first,
      work_email_address: person.emails.where(kind: 'work').first,
      home_phone: person.phones.where(kind: 'home').first,
      work_phone: person.phones.where(kind: 'work').first,
      mobile_phone: person.phones.where(kind: 'mobile').first,
      person_params: {middle_name: 'NewMiddleName', is_incarcerated: true},
      mailing_address_params: {},
      destroyed_mailing_address_params: {},
      home_address_params: {},
      consumer_role_attributes: {is_applying_coverage: true},
      lawful_presence_determination_attributes: {},
      home_email_hash: {},
      work_email_hash: {},
      home_phone_hash: {},
      work_phone_hash: {},
      mobile_phone_hash: {},
      changes: [],
      different_values: []
    }
  end

  context "Success" do
    before do
      @result = subject.call(update_data)
    end

    it "returns success" do
      expect(@result.success?).to be_truthy
    end

    it "updates person attributes" do
      person.reload
      expect(person.middle_name).to eq('NewMiddleName')
    end

    it "updates consumer role attributes" do
      person.reload
      expect(person.consumer_role.is_applying_coverage).to eq(true)
    end
  end

  context "Failure" do

    it "returns failure" do
      expect(subject.call({}).failure?).to be_truthy
    end
  end
end