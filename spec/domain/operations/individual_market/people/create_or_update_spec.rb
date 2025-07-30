# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::People::CreateOrUpdate, type: :model, dbclean: :after_each do
  let(:application) { FactoryBot.create(:individual_market_application, :determined, family_id: family.id) }
  let(:primary_applicant) do
    FactoryBot.create(
      :individual_market_applicant,
      :with_person_name,
      :with_ivl_eligibility,
      :with_immigration_information,
      family_member_id: family.primary_family_member.id,
      addresses: [primary_address],
      emails: [primary_email],
      phones: [primary_phone],
      application: application,
      demographics: female_demographics,
      is_primary_applicant: true
    )
  end

  let(:female_demographics) { FactoryBot.build(:individual_market_demographics, gender: 'female', race: ['White', "Samoan"], ethnicity: ['Mexican', "Cuban"]) }

  let(:primary_email) { FactoryBot.build(:location_email, kind: 'home', address: primary_email_1) }

  let(:primary_email_1) { 'primary_email@home.com' }

  let(:primary_phone) { FactoryBot.build(:location_phone, kind: 'home', area_code: '098', number: primary_phone_number) }

  let(:primary_phone_number) { '7654321' }

  let(:primary_address_1) { '123 New Testing St' }

  let(:primary_address) do
    FactoryBot.build(
      :financial_assistance_address,
      kind: 'home',
      address_1: primary_address_1,
      city: 'Washington',
      state: 'DC',
      zip: '20001'
    )
  end

  let(:secondary_applicant) do
    FactoryBot.create(
      :individual_market_applicant,
      :dependent,
      :with_alternate_person_name,
      :with_ivl_eligibility,
      :with_alternate_demographics,
      family_member_id: nil,
      addresses: [secondary_address],
      emails: [secondary_email],
      phones: [secondary_phone],
      application: application
    )
  end

  let(:secondary_email) { FactoryBot.build(:location_email, kind: 'home', address: 'secondary_email@home.com') }
  let(:secondary_phone) { FactoryBot.build(:location_phone, kind: 'home', area_code: '123', number: '4567890') }

  let(:secondary_address) do
    FactoryBot.build(
      :location_address,
      kind: 'home',
      address_1: '456 Testing St',
      city: 'Washington',
      state: 'DC',
      zip: '20001'
    )
  end

  let(:relationship) { application.relationships.create(relative_id: primary_applicant.id, source_id: secondary_applicant.id, kind: 'spouse') }
  let(:primary_person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) {  FactoryBot.create(:family, :with_primary_family_member, person: primary_person) }

  before :each do
    primary_applicant
    secondary_applicant
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
  end

  describe '#call' do
    context "when: secondary applicant does have ssn and no person associated" do
      it 'should create a person with no ssn' do
        secondary_applicant.demographics.update!(no_ssn: true)
        result = subject.call(applicant: secondary_applicant).value!
        expect(result.first_name).to eq(secondary_applicant.person_name.given_name)
        expect(result.no_ssn).to eq "1"
      end
    end

    context "when: secondary applicant is dependent and address_same_as_primary is true" do
      it "should create a person with the same address as the primary applicant" do
        secondary_applicant.addresses.first.update!(address_1: '123 Main St')
        secondary_applicant.address_same_as_primary = true
        result = subject.call(applicant: secondary_applicant).value!
        expect(result.first_name).to eq(secondary_applicant.person_name.given_name)
        expect(result.addresses.first.address_1).to eq(primary_address_1)
      end
    end

    context "when: secondary applicant is dependent and address_same_as_primary is false" do
      it "should create a person with the same address as the secondary applicant" do
        secondary_applicant.address_same_as_primary = false
        result = subject.call(applicant: secondary_applicant).value!
        expect(result.first_name).to eq(secondary_applicant.person_name.given_name)
        expect(result.addresses.first.address_1).to eq(secondary_address.address_1)
      end
    end
  end
end
