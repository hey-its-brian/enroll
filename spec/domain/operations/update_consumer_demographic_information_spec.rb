# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Operations::UpdateConsumerDemographicInformation, type: :model, dbclean: :after_each do

  let(:person) { FactoryBot.create(:person, :with_consumer_role, middle_name: "John", no_ssn: nil, is_incarcerated: false) }
  let(:consumer_role) { person.consumer_role }
  let(:lawful_presence_determination) { consumer_role.lawful_presence_determination }

  let!(:home_address) { FactoryBot.create(:address, kind: 'home', person: person) }
  let!(:mailing_address) { FactoryBot.create(:address, kind: 'mailing', person: person) }
  let!(:county_zip) { ::BenefitMarkets::Locations::CountyZip.create!(county_name: "Lincoln", zip: "04556", state: "ME") }

  let!(:home_phone) { FactoryBot.create(:phone, kind: 'home', person: person) }
  let!(:work_phone) { FactoryBot.create(:phone, kind: 'work', person: person) }
  let!(:mobile_phone) { FactoryBot.create(:phone, kind: 'mobile', person: person) }

  let(:file_path) { "#{Rails.root}/consumers_needing_updates.csv" }
  let(:output_path) { Rails.root.join('spec', 'test_data', 'changes_made_spec.csv') }
  let(:output_path_2) { Rails.root.join('spec', 'test_data', 'different_changes_spec.csv') }
  let(:logger_path) { Rails.root.join('spec', 'test_data', 'report_logger_spec.csv') }

  let(:publish_instance) { instance_double(Operations::UpdateConsumerDemographicInformation) }

  let(:setting) { double }

  let(:csv_row) do
    {
      'hbx_id' => person.hbx_id,
      'diff1_attribute' => 'middle_name',
      'diff1_report1_value' => 'NewMiddleName',
      'diff1_report2_value' => person.middle_name,
      'diff2_attribute' => 'no_ssn',
      'diff2_report1_value' => '0',
      'diff2_report2_value' => nil,
      'diff3_attribute' => 'tribal_state',
      'diff3_report1_value' => 'ME',
      'diff3_report2_value' => nil,
      'diff4_attribute' => 'is_incarcerated',
      'diff4_report1_value' => "",
      'diff4_report2_value' => "false",
      'diff5_attribute' => 'citizen_status',
      'diff5_report1_value' => "us_citizen",
      'diff5_report2_value' => "",
      'diff6_attribute' => 'home_address_1',
      'diff6_report1_value' => "123 New St",
      'diff6_report2_value' => person.home_address.address_1,
      'diff7_attribute' => 'home_city',
      'diff7_report1_value' => "NewCity",
      'diff7_report2_value' => person.home_address.city,
      'diff8_attribute' => 'home_zip',
      'diff8_report1_value' => "04556",
      'diff8_report2_value' => person.home_address.zip,
      'diff9_attribute' => 'home_email_address',
      'diff9_report1_value' => "test@test1.com",
      'diff9_report2_value' => person.emails.where(kind: 'home').first.address,
      'diff10_attribute' => 'mobile_phone_number',
      'diff10_report1_value' => "555-555-5555",
      'diff10_report2_value' => mobile_phone.full_phone_number,
      'diff11_attribute' => 'is_applying_coverage',
      'diff11_report1_value' => "true",
      'diff11_report2_value' => "false"
    }
  end

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).and_return(true)
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:display_county).and_return(true)
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_quadrant).and_return(false)
    allow(EnrollRegistry).to receive(:[]).with(:enroll_app).and_return(setting)
    allow(setting).to receive(:setting).with(:state_abbreviation).and_return(double(item: 'ME'))
    # allow(File).to receive(:exist?).with(file_path).and_return(true)
    # allow(publish_instance).to receive(:call).with(hbx_id: primary1_hbx_id, force_sync: false).and_return(
        # Success(message1)
        # )
  end

  context "Success" do

    before do
      allow(CSV).to receive(:foreach).with(file_path, headers: true).and_yield(CSV::Row.new(csv_row.keys, csv_row.values))
      allow(File).to receive(:write).with(any_args).and_return(true)
      @result = subject.call(file_path: file_path)
    end
    it "returns a success" do
      expect(@result.success?).to be_truthy
    end
  end

  context "Failure" do
    before do
      allow(CSV).to receive(:foreach).with(file_path, headers: true).and_yield(CSV::Row.new(csv_row.keys, csv_row.values))
      allow(File).to receive(:write).with(any_args).and_return(true)
      @result = subject.call(file_path: '')
    end

    it "returns a failure" do
      expect(@result.failure).to eq("File path is missing")
    end
  end

  context "Updates made" do
    before do
      person.consumer_role.update_attributes!(is_applying_coverage: false)
      lawful_presence_determination.update(citizen_status: nil)
      allow(CSV).to receive(:foreach).with(file_path, headers: true).and_yield(CSV::Row.new(csv_row.keys, csv_row.values))
      allow(File).to receive(:write).with(any_args).and_return(true)
      subject.call(file_path: file_path)
    end

    context "updating person attributes" do
      it "updates the person's middle name" do
        person.reload
        expect(person.middle_name).to eq('NewMiddleName')
      end

      it "updates the person's no ssn value" do
        person.reload
        expect(person.no_ssn).to eql("0")
      end

      it "updates the person's tribal state" do
        person.reload
        expect(person.tribal_state).to eql('ME')
      end

      it "updates the person's incarceration status" do
        person.reload
        expect(person.is_incarcerated).to eql(nil)
      end

      it "updates the person's is_applying_coverage" do
        person.reload
        expect(person.consumer_role.is_applying_coverage).to eql(true)
      end
    end

    context "updating lawful presence determination attributes" do
      it "updates the person's citizen status" do
        person.reload
        expect(person.citizen_status).to eq('us_citizen')
      end
    end

    context "updating addresses" do
      it "updates the person's home address address_1" do
        person.reload
        expect(person.home_address.address_1).to eq('123 New St')
      end

      it "updates the person's home address city" do
        person.reload
        expect(person.home_address.city).to eql("NewCity")
      end

      it "updates the person's home address county" do
        person.reload
        expect(person.home_address.county).to eql("Lincoln")
      end
    end

    context "updating phones" do
      it "updates the person's mobile phone number" do
        mobile_phone.reload
        expect(mobile_phone.full_phone_number).to eq('5555555555')
      end
    end

    context "updating emails" do
      let(:home_email) { person.emails.where(kind: 'home').first }
      it "updates the person's home email" do
        home_email.reload
        expect(home_email.address).to eq('test@test1.com')
      end
    end
  end

  context "building addresses" do

    let(:csv_row_1) do
      {
        'hbx_id' => person.hbx_id,
        'diff1_attribute' => 'mailing_address_1',
        'diff1_report1_value' => 'MailingAddressSt',
        'diff1_report2_value' => "",
        'diff2_attribute' => 'mailing_city',
        'diff2_report1_value' => 'NewCity',
        'diff2_report2_value' => "",
        'diff3_attribute' => 'mailing_state',
        'diff3_report1_value' => 'ME',
        'diff3_report2_value' => "",
        'diff4_attribute' => 'mailing_zip',
        'diff4_report1_value' => "04556",
        'diff4_report2_value' => "",
        'diff5_attribute' => 'mailing_county',
        'diff5_report1_value' => "Lincoln",
        'diff5_report2_value' => ""
      }
    end

    before do
      person.mailing_address.destroy!
      person.reload
      allow(CSV).to receive(:foreach).with(file_path, headers: true).and_yield(CSV::Row.new(csv_row_1.keys, csv_row_1.values))
      allow(File).to receive(:write).with(any_args).and_return(true)
      subject.call(file_path: file_path)
    end

    it "creates a mailing address street" do
      person.reload
      expect(person.mailing_address.address_1).to eq('MailingAddressSt')
    end

    it "creates a mailing address city" do
      person.reload
      expect(person.mailing_address.city).to eq('NewCity')
    end

    it "creates a mailing address zip" do
      person.reload
      expect(person.mailing_address.zip).to eq('04556')
    end

    it "creates a mailing address state" do
      person.reload
      expect(person.mailing_address.state).to eq('ME')
    end

    it "creates a mailing address county" do
      person.reload
      expect(person.mailing_address.county).to eq('Lincoln')
    end
  end

  context "Values do not change due to updated attribute" do
    let(:middle_name) { person.middle_name }

    let(:csv_row_2) do
      {
        'hbx_id' => person.hbx_id,
        'diff1_attribute' => 'middle_name',
        'diff1_report1_value' => 'OldMiddleName',
        'diff1_report2_value' => "NewMiddleName",
        'diff2_attribute' => 'no_ssn',
        'diff2_report1_value' => '0',
        'diff2_report2_value' => nil
      }
    end

    before do
      person.update_attributes!(no_ssn: "1")
      allow(CSV).to receive(:foreach).with(file_path, headers: true).and_yield(CSV::Row.new(csv_row_2.keys, csv_row_2.values))
      allow(File).to receive(:write).with(any_args).and_return(true)
      subject.call(file_path: file_path)
    end

    it "does not change the person's middle name" do
      person.reload
      expect(middle_name).to eq(person.middle_name)
    end

    it "does not change the person's no ssn value" do
      person.reload
      expect(person.no_ssn).to eq("1")
    end
  end

  context "CSV generation" do
    let(:csv_row_3) do
      {
        'hbx_id' => person.hbx_id,
        'diff1_attribute' => 'middle_name',
        'diff1_report1_value' => 'NewMiddleName',
        'diff1_report2_value' => person.middle_name
      }
    end

    let(:date) { DateTime.now.strftime('%Y_%m_%d') }

    let!(:middle_name) { person.middle_name }

    before do
      allow(CSV).to receive(:foreach).with(file_path, headers: true).and_yield(CSV::Row.new(csv_row_3.keys, csv_row_3.values))
      allow(File).to receive(:write).with(any_args).and_return(true)
      subject.call(file_path: file_path)
    end

    it 'logs the before and after changes' do
      person.reload
      csv_file_name = "changes_made_#{date}.csv"
      csv = CSV.read(csv_file_name)
      expect(csv[1]).to eq([person.hbx_id, 'middle_name', middle_name, csv_row_3['diff1_report1_value']])
    end
  end
end
