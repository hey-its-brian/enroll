# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::ContactProfile::FindConsumersBySmsNumber, "given a phone number with no country code which matches no consumers" do
  subject { described_class.new }

  let(:phone_number) do
    "4431234000"
  end

  before :each do
    Person.where({}).delete
  end

  it "finds nothing" do
    expect(Person).to receive(:where).with(
      {
        phones: {
          "$elemMatch" => {
            "$or" => [
              {
                :full_phone_number => {
                  "$in" => ["4431234000", "14431234000", "+14431234000"]
                },
                :kind => "mobile"
              },
              {
                :country_code => "1",
                :area_code => "443",
                :kind => "mobile",
                :number => "1234000"
              }
            ]
          }
        },
        :consumer_role => { "$exists" => true }
      }
    ).and_call_original
    result = subject.call(phone_number)
    expect(result.success?).to be_truthy
    expect(result.value!).to eq []
  end
end

RSpec.describe Operations::ContactProfile::FindConsumersBySmsNumber, "given a phone number with no country code which matches multiple consumers" do
  subject { described_class.new }

  let(:phone_number) do
    "4431234000"
  end

  before :each do
    Person.where({}).delete
  end

  before :each do
    Person.where({}).delete
    @person_1 = FactoryBot.create(:person, :with_consumer_role)
    @person_2 = FactoryBot.create(:person, :with_consumer_role)

    person_1_phone = @person_1.phones[0]
    person_1_phone.kind = "mobile"
    person_1_phone.full_phone_number = phone_number
    person_1_phone.save!

    person_2_phone = @person_2.phones[0]
    person_2_phone.full_phone_number = nil
    person_2_phone.kind = "mobile"
    person_2_phone.country_code = "1"
    person_2_phone.area_code = "443"
    person_2_phone.number = "1234000"
    person_2_phone.full_phone_number = "+14431234000"
    person_2_phone.save!
  end

  after :each do
    Person.where({}).delete
  end

  it "finds those records" do
    result = subject.call(phone_number)
    expect(result.success?).to be_truthy
    expect(result.value!.to_a).to include(@person_1)
    expect(result.value!.to_a).to include(@person_2)
  end
end

RSpec.describe Operations::ContactProfile::FindConsumersBySmsNumber, "given a phone number with a country code which matches no consumers" do
  subject { described_class.new }

  let(:phone_number) do
    "+14431234000"
  end

  before :each do
    Person.where({}).delete
  end

  it "finds nothing" do
    expect(Person).to receive(:where).with(
      {
        phones: {
          "$elemMatch" => {
            "$or" => [
              {
                :full_phone_number => {
                  "$in" => ["4431234000", "14431234000", "+14431234000"]
                },
                :kind => "mobile"
              },
              {
                :country_code => "1",
                :area_code => "443",
                :kind => "mobile",
                :number => "1234000"
              }
            ]
          }
        },
        :consumer_role => { "$exists" => true }
      }
    ).and_call_original
    result = subject.call(phone_number)
    expect(result.success?).to be_truthy
    expect(result.value!).to eq []
  end
end

RSpec.describe Operations::ContactProfile::FindConsumersBySmsNumber, "given a phone number with a country code which matches multiple consumers" do
  subject { described_class.new }

  let(:phone_number) do
    "+14431234000"
  end

  before :each do
    Person.where({}).delete
    @person_1 = FactoryBot.create(:person, :with_consumer_role)
    @person_2 = FactoryBot.create(:person, :with_consumer_role)

    person_1_phone = @person_1.phones[0]
    person_1_phone.kind = "mobile"
    person_1_phone.full_phone_number = "4431234000"
    person_1_phone.save!

    person_2_phone = @person_2.phones[0]
    person_2_phone.full_phone_number = nil
    person_2_phone.kind = "mobile"
    person_2_phone.country_code = "1"
    person_2_phone.area_code = "443"
    person_2_phone.number = "1234000"
    person_2_phone.full_phone_number = "+14431234000"
    person_2_phone.save!
  end

  after :each do
    Person.where({}).delete
  end

  it "finds those records" do
    result = subject.call(phone_number)
    expect(result.success?).to be_truthy
    expect(result.value!.to_a).to include(@person_1)
    expect(result.value!.to_a).to include(@person_2)
  end
end