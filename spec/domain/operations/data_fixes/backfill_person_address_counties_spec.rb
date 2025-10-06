# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::DataFixes::BackfillPersonAddressCounties, type: :model, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:county_zip) { FactoryBot.create(:benefit_markets_locations_county_zip, zip: '20001', county_name: 'Washington', state: 'DC') }

  let(:address) do
    addr = FactoryBot.build(:address,
                            kind: 'home',
                            address_1: '123 Main St',
                            city: 'Washington',
                            state: 'DC',
                            zip: '20001')
    addr.county = nil
    addr
  end

  before do
    county_zip
    person.addresses.clear
    person.addresses << address
    person.save(validate: false)
  end

  it 'should be a container-ready operation' do
    expect(subject.respond_to?(:call)).to be_truthy
  end

  context 'with valid person_hbx_id' do
    context 'success' do
      it 'returns success' do
        @result = subject.call(person_hbx_id: person.hbx_id)
        expect(@result).to be_success
      end

      it 'returns the person' do
        @result = subject.call(person_hbx_id: person.hbx_id)
        expect(@result.success).to eq(person)
      end

      it 'updates the address county' do
        expect(person.addresses.first.county).to be_nil
        @result = subject.call(person_hbx_id: person.hbx_id)
        person.reload
        expect(person.addresses.first.county).to eq('Washington')
      end
    end

    context 'when county is placeholder text' do
      let(:address) do
        addr = FactoryBot.build(:address,
                                kind: 'home',
                                address_1: '123 Main St',
                                city: 'Washington',
                                state: 'DC',
                                zip: '20001')
        addr.county = 'Please provide a zip code'
        addr
      end

      it 'updates the address county' do
        expect(person.addresses.first.county).to eq('Please provide a zip code')
        @result = subject.call(person_hbx_id: person.hbx_id)
        person.reload
        expect(person.addresses.first.county).to eq('Washington')
      end
    end

    context 'when zip code is not found' do
      let(:address) do
        addr = FactoryBot.build(:address,
                                kind: 'home',
                                address_1: '123 Main St',
                                city: 'Washington',
                                state: 'DC',
                                zip: '99999',
                                county: nil)
        addr.county = nil
        addr
      end

      it 'returns success' do
        @result = subject.call(person_hbx_id: person.hbx_id)
        expect(@result).to be_success
      end

      it 'does not update county' do
        expect(person.addresses.first.county).to be_nil
        @result = subject.call(person_hbx_id: person.hbx_id)
        person.reload
        expect(person.addresses.first.county).to be_nil
      end
    end
  end

  context 'with invalid person_hbx_id' do
    before do
      @result = subject.call(person_hbx_id: 'invalid_hbx_id')
    end

    it 'returns failure' do
      expect(@result).to be_failure
    end

    it 'returns primary_person_not_found error' do
      expect(@result.failure).to eq(:primary_person_not_found)
    end
  end

  context 'with financial assistance applications' do
    let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
    let(:applicant) { FactoryBot.create(:applicant, application: application, family_member_id: family.primary_family_member.id) }

    let(:applicant_address) do
      addr = FactoryBot.build(:financial_assistance_address,
                              kind: 'home',
                              address_1: '456 Test Ave',
                              city: 'Washington',
                              state: 'DC',
                              zip: '20001')
      addr.county = nil
      addr
    end

    before do
      applicant.addresses.clear
      applicant.addresses << applicant_address
      applicant.save(validate: false)
    end

    it 'returns success' do
      @result = subject.call(person_hbx_id: person.hbx_id)
      expect(@result).to be_success
    end

    it 'updates the applicant address county' do
      expect(applicant.addresses.first.county).to be_nil
      @result = subject.call(person_hbx_id: person.hbx_id)
      applicant.reload
      expect(applicant.addresses.first.county).to eq('Washington')
    end
  end
end

