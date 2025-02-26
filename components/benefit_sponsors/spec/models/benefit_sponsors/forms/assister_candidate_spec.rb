# frozen_string_literal: true

require "rails_helper"

RSpec.describe BenefitSponsors::Forms::AssisterCandidate, type: :model, dbclean: :after_each do

  let!(:site) { FactoryBot.create(:benefit_sponsors_site, :with_benefit_market, :as_hbx_profile, :cca) }
  let!(:assister_agency_profile) do
    org = FactoryBot.create(:benefit_sponsors_organizations_general_organization, :with_assister_agency_profile, site: site)
    org.assister_agency_profile
  end

  let(:assister_role) { FactoryBot.build(:assister_role, assister_org_id: '234567890') }
  let(:person_obj) { FactoryBot.create(:person, :with_ssn, first_name: "steve", last_name: "smith", dob: "10/10/1974") }

  let(:attributes) do
    {
      assister_applicant_type: "assister",
      first_name: "firstname",
      last_name: "lastname",
      dob: "1993-06-03",
      email: "useraccount@gmail.com",
      assister_org_id: "234567895",
      assister_agency_id: assister_agency_profile.id,
      market_kind: 'shop',
      languages_spoken: ['en'],
      working_hours: true,
      accept_new_clients: false
    }.merge(other_attributes)
  end

  let(:other_attributes) { { } }

  subject do
    BenefitSponsors::Forms::AssisterCandidate.new(attributes)
  end

  it "should have addresses when initialize" do
    assister = BenefitSponsors::Forms::AssisterCandidate.new
    expect(assister.addresses.class).to eq Array
    expect(assister.addresses.first.kind).to eq 'home'
  end

  context 'when email address invalid' do

    it 'should have error on email' do
      assister = BenefitSponsors::Forms::AssisterCandidate.new(attributes.merge({email: "test@email"}))
      assister.valid?
      expect(assister.errors[:email]).not_to be_empty
      expect(assister.errors[:email]).to eq(["test@email is not a valid email"])
    end
  end

  context 'when data missing' do

    let(:attributes) { { assister_applicant_type: 'staff' } }

    before :each do
      subject.valid?
    end

    it "should validate dob" do
      expect(subject.errors[:dob]).not_to be_empty
    end

    it "should validate first_name" do
      expect(subject.errors[:first_name]).not_to be_empty
    end

    it "should validate last_name" do
      expect(subject.errors[:last_name]).not_to be_empty
    end

    it "should validate email" do
      expect(subject.errors[:email]).not_to be_empty
    end
  end

  describe 'Assister assister_org_id validations' do

    before :each do
      subject.valid?
    end

    context 'when Applicant is a assister and assister_org_id is missing' do
      let(:attributes) { { assister_applicant_type: 'assister' } }

      it "should raise an error" do
        expect(subject.errors[:assister_org_id]).not_to be_empty
      end
    end

    context 'when Applicant is assister and assister_org_id is present' do
      let(:attributes) { { assister_org_id: '344232423', assister_applicant_type: 'assister' } }

      it "should pass" do
        expect(subject.errors[:assister_org_id]).to be_empty
      end
    end

    context 'when Applicant is a assister agency staff member and assister_org_id is missing' do
      let(:attributes) { { assister_applicant_type: 'staff' } }

      it "should skip assister_org_id validation" do
        expect(subject.errors[:assister_org_id]).to be_empty
      end
    end
  end

  context 'when Assister enters a duplicate assister_org_id' do

    let(:other_attributes) do
      {
        assister_org_id: "234567890"
      }
    end

    it "should raise an error" do
      person_obj.assister_role = assister_role
      subject.valid?
      expect(subject.errors.to_hash[:base]).to include("Assister Organization ID has already been claimed by another assister. Please contact HBX.")
    end
  end

  describe "Assister Agency validations" do

    before :each do
      subject.valid?
    end

    context 'when assister agency missing' do
      let(:other_attributes) do
        {
          assister_agency_id: nil
        }
      end

      it "should raise an error" do
        expect(subject.errors.to_hash[:base]).to include("Please select your assister agency.")
      end
    end

    context 'when assister agency not found in database' do
      let(:other_attributes) do
        {
          assister_agency_id: "55929d867261670838550000"
        }
      end

      it "should raise an error" do
        expect(subject.errors.to_hash[:base]).to include("Unable to locate the assister agnecy. Please contact HBX.")
      end
    end
  end

  describe ".save" do

    context 'when multiple people matched with the entered personal information' do
      let(:other_attributes) do
        {
          first_name: "john",
          last_name: "smith",
          dob: "1974-10-10"
        }
      end

      before(:each) do
        2.times { FactoryBot.create(:person, :with_ssn, first_name: "john", last_name: "smith", dob: "10/10/1974") }
        subject.save
      end

      it 'should raise an error' do
        expect(subject.errors.to_hash[:base]).to include("Too many people match the criteria provided for your identity. Please contact HBX-Customer Service.")
      end
    end

    describe 'for assister applicant' do

      context 'when no person match found' do
        it 'should save new person with assister role' do
          expect(Person.where(first_name: subject.first_name, last_name: subject.last_name, dob: subject.dob)).to be_empty
          subject.save
          person = Person.where(first_name: subject.first_name, last_name: subject.last_name, dob: subject.dob).first
          expect(person).to be_truthy
          expect(person.assister_role).not_to be_falsey
          expect(person.assister_agency_staff_roles).to be_empty
          expect(person.assister_role.assister_org_id).to eq(attributes[:assister_org_id])
          expect(person.assister_role.benefit_sponsors_assister_agency_profile_id).to eq(attributes[:assister_agency_id])
          expect(person.assister_role.market_kind).to eq attributes[:market_kind]
          expect(person.assister_role.languages_spoken).to eq attributes[:languages_spoken]
          expect(person.assister_role.working_hours).to eq attributes[:working_hours]
          expect(person.assister_role.accept_new_clients).to eq attributes[:accept_new_clients]
        end
      end

      context 'when matched with existing person' do
        let(:other_attributes) do
          {
            first_name: "kevin",
            assister_org_id: '333232324'
          }
        end

        before(:each) do
          FactoryBot.create(:person, :with_ssn, first_name: 'kevin', last_name: subject.last_name, dob: subject.dob)
        end

        it 'should update existing person with assister role' do
          expect(Person.where(first_name: 'kevin', last_name: subject.last_name, dob: subject.dob)).not_to be_empty
          subject.save
          person = Person.where(first_name: 'kevin', last_name: subject.last_name, dob: subject.dob).first
          expect(person).to be_truthy
          expect(person.assister_role).to be_truthy
          expect(person.assister_agency_staff_roles).to be_empty
          expect(person.assister_role.assister_org_id).to eq(attributes[:assister_org_id])
          expect(person.assister_role.benefit_sponsors_assister_agency_profile_id).to eq(attributes[:assister_agency_id])
          expect(person.assister_role.market_kind).to eq attributes[:market_kind]
          expect(person.assister_role.languages_spoken).to eq attributes[:languages_spoken]
          expect(person.assister_role.working_hours).to eq attributes[:working_hours]
          expect(person.assister_role.accept_new_clients).to eq attributes[:accept_new_clients]
        end
      end
    end

    describe 'for assister agency staff member' do

      context 'when no person match found' do
        let(:other_attributes) do
          {
            first_name: "james",
            assister_applicant_type: "staff"
          }
        end

        it 'should save new person with assister staff role' do
          expect(Person.where(first_name: "james", last_name: subject.last_name, dob: subject.dob)).to be_empty
          subject.save
          person = Person.where(first_name: "james", last_name: subject.last_name, dob: subject.dob).first
          expect(person).to be_truthy
          expect(person.assister_role).to be_falsey
          expect(person.assister_agency_staff_roles.count).to eq(1)
          expect(person.assister_agency_staff_roles[0].benefit_sponsors_assister_agency_profile_id).to eq(attributes[:assister_agency_id])
        end
      end

      context 'when matched with existing person' do
        let(:other_attributes) do
          {
            first_name: "joe",
            assister_applicant_type: "staff"
          }
        end

        before(:each) do
          FactoryBot.create(:person, :with_ssn, first_name: 'joe', last_name: subject.last_name, dob: subject.dob)
        end

        it 'should update existing person with assister staff role' do
          expect(Person.where(first_name: 'joe', last_name: subject.last_name, dob: subject.dob)).not_to be_empty
          subject.save
          person = Person.where(first_name: "joe", last_name: subject.last_name, dob: subject.dob).first
          expect(person).to be_truthy
          expect(person.assister_role).to be_falsey
          expect(person.assister_agency_staff_roles.count).to eq(1)
          expect(person.assister_agency_staff_roles[0].benefit_sponsors_assister_agency_profile_id).to eq(attributes[:assister_agency_id])
        end
      end

      context 'address' do
        let(:other_attributes) do
          {
            :addresses_attributes => {"0" => {
              kind: 'home',
              address_1: 'Street NE',
              city: 'Washington',
              state: 'DC',
              zip: '12345'
            }}
          }
        end

        before(:each) do
          Person.delete_all
          FactoryBot.create(:person, :with_ssn, first_name: subject.first_name, last_name: subject.last_name, dob: subject.dob)
        end

        it 'should update existing person with addresses' do
          expect(Person.where(first_name: subject.first_name, last_name: subject.last_name, dob: subject.dob)).not_to be_empty
          subject.save

          person = Person.where(first_name: subject.first_name, last_name: subject.last_name, dob: subject.dob).first

          expect(person).to be_truthy
          expect(person.addresses.last.address_1).to eq 'Street NE'
          expect(person.addresses.last.city).to eq 'Washington'
          expect(person.addresses.last.state).to eq 'DC'
          expect(person.addresses.last.zip).to eq '12345'
        end
      end
    end
  end
end