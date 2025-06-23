# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::Families::CreateOrUpdate, type: :model, dbclean: :after_each do
  let(:application) { FactoryBot.create(:individual_market_application, :determined, family_id: family.id) }
  let(:primary_applicant) do
    FactoryBot.create(
      :individual_market_applicant,
      :with_person_name,
      :with_ivl_eligibility,
      :with_immigration_information,
      family_member_id: primary_family_member_id,
      addresses: [primary_address],
      emails: [primary_email],
      phones: [primary_phone],
      application: application,
      demographics: female_demographics
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
      family_member_id: secondary_family_member_id,
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
  let(:primary_family_member_id) { family.primary_applicant.id }
  let(:returned_family) { @result.success[1] }

  describe '#call' do
    # Deactivation of a family member who is not present on the application
    context "when:
      - primary applicant's family member and person exists
      - primary_applicant's information is different from the existing person
      - secondary applicant does not exist
      - dependent family member with person exists
    " do

      let(:secondary_person) do
        per = FactoryBot.create(:person, :with_consumer_role)
        primary_person.person_relationships.create(relative_id: per.id, kind: 'child')
        per
      end
      let(:secondary_family_member) { FactoryBot.create(:family_member, family: family, person: secondary_person) }
      let(:secondary_family_member_id) { secondary_family_member.id }

      before :each do
        secondary_family_member
        @result = subject.call(application: primary_applicant.application)
        primary_person.reload
        secondary_person.reload
        family.reload
        application.reload
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'assigns latest application GID' do
        expect(family.latest_application_gid).to eq(application.to_global_id.uri.to_s)
      end

      it "updates the primary person's gender" do
        expect(primary_person.gender).to eq('female')
      end

      it 'update the race to be a string' do
        expect(primary_person.race).to eq('White, Samoan')
      end

      it 'builds lawful presence determination' do
        expect(primary_person.consumer_role.lawful_presence_determination).to be_present
      end

      it 'builds VLP document' do
        expect(primary_person.consumer_role.active_vlp_document_id).to be_present
      end

      it 'update the ethnicity to include race values' do
        expect(primary_person.ethnicity).to include('White')
        expect(primary_person.ethnicity).to include('Samoan')
      end

      it 'deactivates the secondary family member' do
        expect(secondary_family_member.reload.is_active).to be_falsey
      end

      it 'removes coverage household member for the deleted family member' do
        member_ids = family.reload.active_household.coverage_households.first.coverage_household_members.map(&:family_member_id)
        expect(member_ids).not_to include(secondary_family_member.id)
      end

      it 'updates applicants with family_member_id' do
        application.applicants.each do |applicant|
          expect(applicant.family_member_id).to be_present
        end
      end

      it 'updates the application with family_updated_at' do
        expect(application.family_updated_at).to be_present
      end
    end

    context "when:
      - primary applicant's family member and person exists
      - primary_applicant's information is different from the existing person
      - secondary applicant's family member and person exists
      - secondary_applicant's information is different from the existing person" do

      let(:secondary_person) do
        per = FactoryBot.create(:person, :with_consumer_role)
        primary_person.person_relationships.create(relative_id: per.id, kind: 'child')
        per
      end
      let(:secondary_family_member) { FactoryBot.create(:family_member, family: family, person: secondary_person) }
      let(:secondary_family_member_id) { secondary_family_member.id }

      before :each do
        @result = subject.call(application: relationship.application)
        primary_person.reload
        secondary_person.reload
        family.reload
        application.reload
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'assigns latest application GID' do
        expect(family.latest_application_gid).to eq(application.to_global_id.uri.to_s)
      end

      it "updates the primary person's gender" do
        expect(primary_person.gender).to eq('female')
      end

      it 'updates the relationship kind' do
        expect(primary_person.person_relationships.where(relative_id: secondary_person.id).first.kind).to eq('spouse')
      end

      it 'updates primary person with new address and removes old addresses' do
        expect(primary_person.addresses.size).to eq(1)
        expect(primary_person.addresses.first).to have_attributes(
          kind: primary_address.kind,
          address_1: primary_address.address_1,
          city: primary_address.city,
          state: primary_address.state,
          zip: primary_address.zip
        )
      end

      it 'updates primary person with new email and removes old emails' do
        expect(primary_person.emails.size).to eq(1)
        expect(primary_person.emails.first).to have_attributes(
          kind: primary_email.kind,
          address: primary_email.address
        )
      end

      it 'updates primary person with new phone and removes the old phones' do
        expect(primary_person.phones.size).to eq(1)
        expect(primary_person.phones.first).to have_attributes(
          kind: primary_phone.kind,
          area_code: primary_phone.area_code,
          number: primary_phone.number
        )
      end

      it "updates the secondary person's gender" do
        expect(secondary_person.gender).to eq('female')
      end

      it 'updates secondary person with new address and removes old addresses' do
        expect(secondary_person.addresses.size).to eq(1)
        expect(secondary_person.addresses.first).to have_attributes(
          kind: secondary_address.kind,
          address_1: secondary_address.address_1,
          city: secondary_address.city,
          state: secondary_address.state,
          zip: secondary_address.zip
        )
      end

      it 'updates secondary person with new email and removes old emails' do
        expect(secondary_person.emails.size).to eq(1)
        expect(secondary_person.emails.first).to have_attributes(
          kind: secondary_email.kind,
          address: secondary_email.address
        )
      end

      it 'updates secondary person with new phone and removes the old phones' do
        expect(secondary_person.phones.size).to eq(1)
        expect(secondary_person.phones.first).to have_attributes(
          kind: secondary_phone.kind,
          area_code: secondary_phone.area_code,
          number: secondary_phone.number
        )
      end

      it 'updates applicants with family_member_id' do
        application.applicants.each do |applicant|
          expect(applicant.family_member_id).to be_present
        end
      end

      it 'updates the application with family_updated_at' do
        expect(application.family_updated_at).to be_present
      end
    end

    context "when:
      - primary applicant's family member and person exists
      - primary_applicant's information is different from the existing person
      - secondary applicant's family member and person does not exist" do
      let(:new_family_member) { returned_family.family_members.where(id: secondary_applicant.reload.family_member_id).first }

      let(:new_person) { new_family_member.person }

      let(:secondary_family_member_id) { nil }

      before :each do
        @result = subject.call(application: relationship.application)
        primary_person.reload
        family.reload
        application.reload
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'assigns latest application GID' do
        expect(family.latest_application_gid).to eq(application.to_global_id.uri.to_s)
      end

      it 'updates the secondary applicant with the new family member id' do
        expect(family.family_members.map(&:id)).to include(secondary_applicant.family_member_id)
      end

      it 'creates a coverage household member for the applicant' do
        member_ids = family.active_household.coverage_households.first.coverage_household_members.map(&:family_member_id)
        expect(member_ids).to include(secondary_applicant.family_member_id)
      end

      it "updates the existing person's gender" do
        expect(primary_person.gender).to eq('female')
      end

      it 'updates existing person with new address and removes old addresses' do
        expect(primary_person.addresses.size).to eq(1)
        expect(primary_person.addresses.first).to have_attributes(
          kind: primary_address.kind,
          address_1: primary_address.address_1,
          city: primary_address.city,
          state: primary_address.state,
          zip: primary_address.zip
        )
      end

      it 'updates existing person with new email and removes old emails' do
        expect(primary_person.emails.size).to eq(1)
        expect(primary_person.emails.first).to have_attributes(
          kind: primary_email.kind,
          address: primary_email.address
        )
      end

      it 'updates existing person with new phone and removes the old phones' do
        expect(primary_person.phones.size).to eq(1)
        expect(primary_person.phones.first).to have_attributes(
          kind: primary_phone.kind,
          area_code: primary_phone.area_code,
          number: primary_phone.number
        )
      end

      it 'creates a new active family member for the secondary applicant' do
        expect(new_family_member).to be_a(FamilyMember)
        expect(secondary_applicant.family_member_id).to eq(new_family_member.id)
        expect(new_family_member.is_active).to be_truthy
      end

      it 'creates addresses for the new person' do
        expect(new_person.addresses.size).to eq(1)
        expect(new_person.addresses.first).to have_attributes(
          kind: secondary_address.kind,
          address_1: secondary_address.address_1,
          city: secondary_address.city,
          state: secondary_address.state,
          zip: secondary_address.zip
        )
      end

      it 'creates emails for the new person' do
        expect(new_person.emails.size).to eq(1)
        expect(new_person.emails.first).to have_attributes(
          kind: secondary_email.kind,
          address: secondary_email.address
        )
      end

      it 'creates phones for the new person' do
        expect(new_person.phones.size).to eq(1)
        expect(new_person.phones.first).to have_attributes(
          kind: secondary_phone.kind,
          area_code: secondary_phone.area_code,
          number: secondary_phone.number
        )
      end

      it 'updates applicants with family_member_id' do
        application.applicants.each do |applicant|
          expect(applicant.family_member_id).to be_present
        end
      end

      it 'updates the application with family_updated_at' do
        expect(application.family_updated_at).to be_present
      end
    end
  end
end
