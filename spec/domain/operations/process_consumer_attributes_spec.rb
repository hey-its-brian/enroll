# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Operations::ProcessConsumerAttributes, type: :model, dbclean: :after_each do

  let!(:person) { FactoryBot.create(:person, :with_consumer_role) }

  let(:row) do
    {
      'hbx_id' => person.hbx_id,
      'diff1_attribute' => 'middle_name',
      'diff1_report1_value' => 'NewMiddleName',
      'diff1_report2_value' => person.middle_name
    }
  end

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
      person_params: {},
      mailing_address_params: {},
      destroyed_mailing_address_params: {},
      home_address_params: {},
      consumer_role_attributes: {},
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

  let(:attributes) do
    {
      row: row,
      update_data: update_data,
      results: {},
      changed_results: {},
      hbx_id: person.hbx_id
    }
  end

  context "It creates a hash of attributes" do

    before do
      @result = subject.call(attributes)
    end

    it "returns success" do
      expect(@result.success?).to be_truthy
    end

    it "builds a new hash of updated params" do
      expect(attributes[:results]).to eql({person.hbx_id => [['middle_name', person.middle_name, row['diff1_report1_value']]]})
    end

    it "populates the csv hash" do
      expect(attributes[:update_data][:person_params]).to eql({:middle_name => row['diff1_report1_value']})
    end
  end
end