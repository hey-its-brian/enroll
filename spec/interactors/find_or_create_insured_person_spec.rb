# frozen_string_literal: true

require "rails_helper"

describe FindOrCreateInsuredPerson, :dbclean => :after_each do
  let(:first_name) { "Joe" }
  let(:last_name) { "Smith" }
  let(:dob) { Date.new(1988, 3, 10) }
  let(:ssn) { "789834231" }
  let(:user) { FactoryBot.create(:user) }
  let(:result) { FindOrCreateInsuredPerson.call(context_arguments) }

  context "given a person who does not exist" do
    let(:context_arguments) do
      { :first_name => first_name,
        :last_name => last_name,
        :dob => dob,
        :no_ssn => "0"}
    end

    it "should create that person and return them" do
      expect(result.person.first_name).to eq first_name
    end

    it "should communicate it created a new person" do
      expect(result.is_new).to be_truthy
    end

    it "should set no_ssn on the newly created person" do
      expect(result.person.no_ssn).to eq "0"
    end
  end

  context "given a person who does exist" do
    let!(:found_person) { FactoryBot.create(:person, ssn: nil, :first_name => first_name, :last_name => last_name, :dob => dob, :no_ssn => nil) }
    let(:context_arguments) do
      { :first_name => first_name,
        :last_name => last_name,
        :dob => dob,
        :no_ssn => "1"}
    end

    it "should return the found person" do
      expect(result.person).to eq found_person
    end

    it "should communicate that a new person was not created" do
      expect(result.is_new).to be_falsey
    end

    it "should set no_ssn on the existing found person" do
      expect(result.person.no_ssn).to eq "1"
    end
  end

  context "given a person with the same first name, last name, dob, but different ssn exists" do
    let!(:found_person) { FactoryBot.create(:person, ssn: ssn, :first_name => first_name, :last_name => last_name, :dob => dob, :no_ssn => "0") }
    let(:context_arguments) do
      { :first_name => first_name,
        :last_name => last_name,
        :dob => dob,
        :ssn => '123456789',
        :no_ssn => "1"}
    end

    it "should not match with the existing person" do
      expect(Person.all.count).to eq 1
      expect(result.person.ssn).to_not eq ssn
      expect(Person.all.count).to eq 2
    end
  end

  context "given a person who does not exist but SSN is already taken" do
    let!(:found_person) {  FactoryBot.create(:person, ssn: ssn) }
    let(:context_arguments) do
      { :first_name => first_name,
        :last_name => last_name,
        :dob => dob,
        :ssn => ssn}
    end

    it "should just return" do
      expect(result.person).to eq nil
    end

    it "should communicate that a new person was not created" do
      expect(result.is_new).to be_falsey
    end
  end

  context "given an invalid SSN with the :validate_ssn feature flag active" do
    let(:context_arguments) do
      { :first_name => first_name,
        :last_name => last_name,
        :dob => dob}
    end

    before do
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:check_for_crm_updates).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:crm_publish_primary_subscriber).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:validate_ssn).and_return(true)
      allow(EnrollRegistry).to receive(:feature_enabled?).with(:sensor_tobacco_carrier_usage).and_return(false)
    end

    it "will throw an error if the SSN consists of only zeroes" do
      context_arguments[:ssn] = '000000000'
      person = result.person

      expect(person.nil?).to be_truthy
    end

    it "will throw an error if the first three digits of an SSN consists of only zeroes" do
      context_arguments[:ssn] = '000834231'
      person = result.person

      expect(person.nil?).to be_truthy
    end

    it "will throw an error if the first three digits of an SSN consists of only sixes" do
      context_arguments[:ssn] = '666834231'
      person = result.person

      expect(person.nil?).to be_truthy
    end

    it "will throw an error if the first three digits of an SSN is between 900-999" do
      ssn = "#{rand(900..999)}834231"
      context_arguments[:ssn] = ssn
      person = result.person

      expect(person.nil?).to be_truthy
    end

    it "will throw an error if the fourth and fifth digit of an SSN are zeroes" do
      context_arguments[:ssn] = '789004231'
      person = result.person

      expect(person.nil?).to be_truthy
    end

    it "will throw an error if the last four digits of an SSN are zeroes" do
      context_arguments[:ssn] = '789830000'
      person = result.person

      expect(person.nil?).to be_truthy
    end
  end
end
