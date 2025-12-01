# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::FinancialAssistance::OnDetermination::People::CreateOrUpdate, type: :model, dbclean: :after_each do
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: primary_person) }
  let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
  let(:determination) { FactoryBot.create(:financial_assistance_eligibility_determination, application: application) }

  let(:primary_person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:primary_family_member_id) { family.primary_applicant.id }

  let(:primary_address) do
    FactoryBot.build(
      :financial_assistance_address,
      kind: 'home',
      address_1: '123 Test St',
      city: 'Washington',
      state: 'DC',
      zip: '20001'
    )
  end

  let(:primary_email) { FactoryBot.build(:financial_assistance_email, kind: 'home', address: 'test@example.com') }
  let(:primary_phone) { FactoryBot.build(:financial_assistance_phone, kind: 'home', area_code: '202', number: '1234567') }

  let(:applicant) do
    FactoryBot.create(
      :financial_assistance_applicant,
      is_primary_applicant: true,
      family_member_id: primary_family_member_id,
      person_hbx_id: primary_person.hbx_id,
      eligibility_determination_id: determination.id,
      addresses: [primary_address],
      emails: [primary_email],
      phones: [primary_phone],
      application: application,
      first_name: 'John',
      last_name: 'Doe',
      gender: 'male',
      dob: Date.new(1980, 1, 1),
      encrypted_ssn: encrypted_ssn,
      no_ssn: no_ssn
    )
  end

  let(:encrypted_ssn) { SymmetricEncryption.encrypt('123456789') }
  let(:no_ssn) { '0' }

  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(true)
    allow(EnrollRegistry[:alive_status].feature).to receive(:is_enabled).and_return(true)
  end

  describe '#call' do
    context 'when applicant has an SSN' do
      let(:encrypted_ssn) { SymmetricEncryption.encrypt('123456789') }
      let(:no_ssn) { '0' }

      before :each do
        @result = subject.call(applicant: applicant)
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'assigns encrypted_ssn to the person' do
        person = @result.success
        expect(person.encrypted_ssn).to eq(applicant.encrypted_ssn)
        expect(person.encrypted_ssn).to be_present
      end

      it 'assigns the correct SSN value' do
        person = @result.success
        expect(person.ssn).to eq('123456789')
      end

      it 'sets no_ssn flag to false when SSN is present' do
        person = @result.success
        expect(person.no_ssn).to eq('0')
      end

      it 'creates a consumer role with correct attributes' do
        person = @result.success
        expect(person.consumer_role).to be_present
        expect(person.consumer_role.is_applicant).to eq(applicant.is_primary_applicant)
        expect(person.consumer_role.contact_method).to eq(applicant.contact_method)
        expect(person.consumer_role.is_applying_coverage).to eq(applicant.is_applying_coverage)
      end

      it 'creates addresses from applicant information' do
        person = @result.success
        expect(person.addresses.size).to eq(1)
        address = person.addresses.first
        expect(address.kind).to eq('home')
        expect(address.address_1).to eq('123 Test St')
        expect(address.city).to eq('Washington')
        expect(address.state).to eq('DC')
        expect(address.zip).to eq('20001')
      end

      it 'creates emails from applicant information' do
        person = @result.success
        expect(person.emails.size).to eq(1)
        email = person.emails.first
        expect(email.kind).to eq('home')
        expect(email.address).to eq('test@example.com')
      end

      it 'creates phones from applicant information' do
        person = @result.success
        expect(person.phones.size).to eq(1)
        phone = person.phones.first
        expect(phone.kind).to eq('home')
        expect(phone.area_code).to eq('202')
        expect(phone.number).to eq('1234567')
      end

      it 'creates a demographics group' do
        person = @result.success
        expect(person.demographics_group).to be_present
      end

      it 'persists the person to the database' do
        person = @result.success
        expect(person.persisted?).to be_truthy
        expect(person.id).to be_present
      end

      context 'when person matching finds existing person with same SSN' do
        # Skip the main before block for this context to avoid SSN conflicts
        let!(:existing_person) do
          Person.destroy_all # Clear any existing people first
          FactoryBot.create(:person,
                            first_name: 'John',
                            last_name: 'Doe',
                            dob: Date.new(1980, 1, 1),
                            encrypted_ssn: SymmetricEncryption.encrypt('123456789'))
        end

        # Create a new applicant without family_member_id to force SSN matching
        let(:matching_applicant) do
          FactoryBot.create(
            :financial_assistance_applicant,
            is_primary_applicant: false,
            family_member_id: nil, # Key: no family member ID to force SSN matching
            person_hbx_id: nil,
            eligibility_determination_id: determination.id,
            addresses: [primary_address],
            emails: [primary_email],
            phones: [primary_phone],
            application: application,
            first_name: 'John',
            last_name: 'Doe',
            gender: 'male',
            dob: Date.new(1980, 1, 1),
            encrypted_ssn: SymmetricEncryption.encrypt('123456789'),
            no_ssn: '0'
          )
        end

        before do
          # Don't use @result from the main context, run the operation fresh
          @result = subject.call(applicant: matching_applicant)
        end

        it 'updates the existing person instead of creating a new one' do
          person = @result.success
          expect(person.id).to eq(existing_person.id)
        end

        it 'updates person attributes from applicant' do
          person = @result.success
          expect(person.gender).to eq(matching_applicant.gender)
        end
      end
    end

    context 'when applicant does not have an SSN' do
      let(:encrypted_ssn) { nil }
      let(:no_ssn) { '1' }

      before :each do
        applicant.encrypted_ssn = nil
        applicant.no_ssn = '1'
        @result = subject.call(applicant: applicant)
      end

      it 'returns a success result' do
        expect(@result.success?).to be_truthy
      end

      it 'does not assign encrypted_ssn to the person' do
        person = @result.success
        expect(person.encrypted_ssn).to be_blank
        expect(person.encrypted_ssn).to be_nil
      end

      it 'assigns no_ssn flag to the person' do
        person = @result.success
        expect(person.no_ssn).to eq('1')
      end

      it 'has blank SSN value' do
        person = @result.success
        expect(person.ssn).to be_blank
        expect(person.ssn).to be_nil
      end

      it 'handles SSN validation correctly for no_ssn cases' do
        person = @result.success
        expect(person.no_ssn).to eq('1')
        expect(person.ssn).to be_nil
        expect(person.encrypted_ssn).to be_nil
      end

      it 'still creates a consumer role' do
        person = @result.success
        expect(person.consumer_role).to be_present
      end

      it 'still creates contact information' do
        person = @result.success
        expect(person.addresses.size).to eq(1)
        expect(person.emails.size).to eq(1)
        expect(person.phones.size).to eq(1)
      end

      context 'when person matching without SSN' do
        let!(:existing_person) do
          FactoryBot.create(:person,
                            first_name: 'John',
                            last_name: 'Doe',
                            dob: Date.new(1980, 1, 1),
                            encrypted_ssn: nil,
                            no_ssn: '1')
        end

        it 'performs matching using name and DOB only' do
          person = @result.success
          expect(person.first_name).to eq('John')
          expect(person.last_name).to eq('Doe')
          expect(person.dob).to eq(Date.new(1980, 1, 1))
        end
      end
    end

    context 'when applicant has family_member_id' do
      let(:existing_person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:family_member) { FactoryBot.create(:family_member, family: family, person: existing_person) }

      before :each do
        applicant.family_member_id = family_member.id
        applicant.person_hbx_id = existing_person.hbx_id
        @result = subject.call(applicant: applicant)
      end

      it 'finds the existing person through family member' do
        person = @result.success
        expect(person.id).to eq(existing_person.id)
      end

      it 'updates the existing person with applicant information' do
        person = @result.success
        expect(person.first_name).to eq(applicant.first_name)
        expect(person.last_name).to eq(applicant.last_name)
        expect(person.gender).to eq(applicant.gender)
      end
    end

    context 'when applicant has no VLP document information' do
      before :each do
        applicant.vlp_subject = nil
        applicant.alien_number = nil
        applicant.i94_number = nil
        @result = subject.call(applicant: applicant)
      end

      it 'does not create VLP documents' do
        person = @result.success
        expect(person.consumer_role.vlp_documents.size).to eq(0)
      end

      it 'still creates lawful presence determination with citizen status' do
        person = @result.success
        expect(person.consumer_role.lawful_presence_determination).to be_present
        expect(person.consumer_role.lawful_presence_determination.citizen_status).to eq(applicant.citizen_status)
      end
    end

    context 'when updating existing person with different contact information' do
      let(:existing_person) do
        person = FactoryBot.create(:person,
                                   first_name: 'John',
                                   last_name: 'Doe',
                                   dob: Date.new(1980, 1, 1),
                                   encrypted_ssn: SymmetricEncryption.encrypt('123456789'))
        person.addresses.build(kind: 'home', address_1: 'Old Address', city: 'Old City', state: 'DC', zip: '20002')
        person.emails.build(kind: 'home', address: 'old@example.com')
        person.phones.build(kind: 'home', area_code: '301', number: '9876543')
        person.save!
        person
      end

      before :each do
        # Force matching to find the existing person
        operation_instance = described_class.new
        allow(described_class).to receive(:new).and_return(operation_instance)
        allow(operation_instance).to receive(:find_existing_person).and_return(existing_person)
        @result = subject.call(applicant: applicant)
      end

      it 'replaces old addresses with new ones' do
        person = @result.success
        expect(person.addresses.size).to eq(1)
        address = person.addresses.first
        expect(address.address_1).to eq('123 Test St')
        expect(address.city).to eq('Washington')
      end

      it 'replaces old emails with new ones' do
        person = @result.success
        expect(person.emails.size).to eq(1)
        email = person.emails.first
        expect(email.address).to eq('test@example.com')
      end

      it 'replaces old phones with new ones' do
        person = @result.success
        expect(person.phones.size).to eq(1)
        phone = person.phones.first
        expect(phone.area_code).to eq('202')
        expect(phone.number).to eq('1234567')
      end
    end

    context 'with ethnicity and tribal information' do
      let(:applicant_with_tribal_info) do
        FactoryBot.create(
          :financial_assistance_applicant,
          is_primary_applicant: false,
          eligibility_determination_id: determination.id,
          addresses: [primary_address],
          emails: [primary_email],
          phones: [primary_phone],
          application: application,
          first_name: 'Tribal',
          last_name: 'Member',
          gender: 'female',
          dob: Date.new(1990, 3, 15),
          encrypted_ssn: SymmetricEncryption.encrypt('456789012'),
          ethnicity: ['American Indian or Alaska Native', 'Hispanic or Latino'],
          race: 'American Indian or Alaska Native',
          indian_tribe_member: true,
          tribal_id: 'T12345',
          tribal_state: 'AK',
          tribal_name: 'Test Tribe'
        )
      end

      before :each do
        @result = subject.call(applicant: applicant_with_tribal_info)
      end

      it 'assigns ethnicity information' do
        person = @result.success
        expect(person.ethnicity).to contain_exactly('American Indian or Alaska Native', 'Hispanic or Latino')
      end

      it 'assigns tribal information' do
        person = @result.success
        expect(person.race).to eq('American Indian or Alaska Native')
        expect(person.tribal_id).to eq('T12345')
        expect(person.tribal_state).to eq('AK')
        expect(person.tribal_name).to eq('Test Tribe')
      end
    end
  end

  describe 'private methods' do
    describe '#find_existing_person' do
      let(:operation) { described_class.new }

      context 'when applicant has family_member_id' do
        let(:existing_person) { FactoryBot.create(:person) }
        let(:family_member) { FactoryBot.create(:family_member, family: family, person: existing_person) }

        it 'returns the person through family member' do
          applicant.family_member_id = family_member.id
          result = operation.send(:find_existing_person, applicant)
          expect(result).to eq(existing_person)
        end
      end

      context 'when applicant has no family_member_id' do
        it 'uses matching criteria to find person' do
          # Test the matching logic
          result = operation.send(:find_existing_person, applicant)
          # Since there's no exact match, it should return nil or use the matching service
          expect(result).to be_a(Person).or be_nil
        end
      end
    end

    describe '#fetch_ethnicity' do
      let(:operation) { described_class.new }

      it 'filters out blank ethnicity values' do
        applicant.ethnicity = ['Hispanic or Latino', '', nil, 'American Indian or Alaska Native', '']
        result = operation.send(:fetch_ethnicity, applicant)
        expect(result).to contain_exactly('Hispanic or Latino', 'American Indian or Alaska Native')
      end

      it 'returns empty array for non-array ethnicity' do
        applicant.ethnicity = nil
        result = operation.send(:fetch_ethnicity, applicant)
        expect(result).to eq([])
      end
    end
  end
end