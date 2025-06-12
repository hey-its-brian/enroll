# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FinancialAssistance::Forms::Applicant, type: :model do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) do
    FactoryBot.create(:family, :with_primary_family_member, :person => person)
  end
  let(:application) { FactoryBot.create(:financial_assistance_application, family: family) }
  let(:primary_applicant) { FactoryBot.create(:financial_assistance_applicant, application: application, is_primary_applicant: true) }

  let(:applicant_properties) do
    { "first_name" => "test",
      "middle_name" => "",
      "last_name" => "fm",
      "dob" => "1982-11-11",
      "ssn" => "",
      "no_ssn" => "1",
      "gender" => "male",
      "tribal_id" => "",
      "ethnicity" => ["", "", "", "", "", "", ""],
      "is_consumer_role" => "true",
      "same_with_primary" => "true",
      "is_homeless" => "false",
      "is_temporarily_out_of_state" => "false",
      "application_id" => application.id,
      "addresses" =>
        { "0" => {"kind" => "home", "address_1" => "", "address_2" => "", "city" => "", "state" => "", "zip" => ""},
          "1" => {"kind" => "mailing", "address_1" => "", "address_2" => "", "city" => "", "state" => "", "zip" => ""}}}
  end

  subject { described_class.new(applicant_properties) }

  before do
    allow(application).to receive(:primary_applicant).and_return(primary_applicant)
    allow(FinancialAssistance::Application).to receive(:find).with(application.id).and_return(application)
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to validate_presence_of(:last_name) }
    it { is_expected.to validate_presence_of(:gender) }
    it { is_expected.to validate_presence_of(:dob) }

    context "when ssn is provided" do
      it "validates length" do
        subject.ssn = "12345"
        expect(subject).not_to be_valid
        expect(subject.errors[:ssn]).to include(" must be 9 digits")
      end
    end
  end

  describe "#has_in_state_home_addresses?" do
    it "validates address within state boundaries" do
      addresses_attrs = {
        "0" => { kind: "home", address_1: "123 Main St", city: "Washington", state: EnrollRegistry[:enroll_app].setting(:state_abbreviation).item, zip: "20001" }
      }

      expect(subject).to receive(:has_in_state_home_addresses?).with(addresses_attrs).and_return(true)
      subject.addresses_attributes = addresses_attrs
      allow(subject).to receive(:valid?).and_return(true)
      allow(subject).to receive(:extract_applicant_params).and_return({})
      subject.save
    end
  end

  describe "#destroy_mailing_address?" do
    it "returns true when conditions are met" do
      address = { kind: "mailing", _destroy: "true", id: "123" }
      expect(subject.destroy_mailing_address?(address)).to be true
    end

    it "returns false when address is not mailing" do
      address = { kind: "home", _destroy: "true", id: "123" }
      expect(subject.destroy_mailing_address?(address)).to be false
    end

    it "returns false when not marked for destruction" do
      address = { kind: "mailing", _destroy: "false", id: "123" }
      expect(subject.destroy_mailing_address?(address)).to be false
    end
  end

  describe "#primary_applicant_address_attributes" do
    let(:home_address) { double(attributes: { "address_1" => "123 Main St", "city" => "DC", "state" => "WA", "zip" => "20001", "kind" => "home" }) }

    before do
      allow(primary_applicant).to receive_message_chain(:addresses, :in, :first).and_return(home_address)
      allow(home_address).to receive(:slice).and_return(home_address.attributes)
    end

    it "copies primary applicant's address" do
      subject.is_dependent = "true"
      subject.same_with_primary = "true"
      expect(subject.primary_applicant_address_attributes).to be_a(Hash)
    end
  end

  context 'when age_off_excluded is true ' do
    subject { FinancialAssistance::Forms::Applicant.new(applicant_properties.merge({age_off_excluded: "true"})) }

    it "should return true" do
      expect(subject.age_off_excluded).to eq "true"
    end
  end

  context 'when us_citizen is false and immigration_status_question is not required' do
    before do
      allow(EnrollRegistry[:immigration_status_question_required].feature).to receive(:is_enabled).and_return(false)
    end

    subject { FinancialAssistance::Forms::Applicant.new(applicant_properties.merge({"us_citizen" => "false", "indian_tribe_member" => "false", "is_incarcerated" => "false"})) }

    it "should return false" do
      subject.eligible_immigration_status = ""
      expect(subject.eligible_immigration_status).to eq false
    end
  end

  context 'when us_citizen is false and immigration_status_question is required' do
    before do
      allow(EnrollRegistry[:immigration_status_question_required].feature).to receive(:is_enabled).and_return(true)
    end

    subject { FinancialAssistance::Forms::Applicant.new(applicant_properties.merge({"us_citizen" => "false", "indian_tribe_member" => "false", "is_incarcerated" => "false"})) }

    it "should return nil" do
      subject.eligible_immigration_status = ""
      expect(subject.eligible_immigration_status).to eq nil
    end
  end
end
