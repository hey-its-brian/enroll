# frozen_string_literal: true

require 'rails_helper'
require 'aca_entities/serializers/xml/medicaid/atp'
require 'aca_entities/atp/transformers/cv/family'

RSpec.describe ::FinancialAssistance::Operations::Transfers::MedicaidGateway::V2::BuildFamilyAndCreateMember, dbclean: :after_each do
  include Dry::Monads[:do, :result]

  let(:xml_file_path) { ::FinancialAssistance::Engine.root.join('spec', 'shared_examples', 'medicaid_gateway', 'Simple_Test_Case_E_New.xml') }
  let(:xml) do
    Rails.cache.fetch("test_xml_string") do
      File.read(xml_file_path)
    end
  end

  let(:serializer) { ::AcaEntities::Serializers::Xml::Medicaid::Atp::AccountTransferRequest }
  let(:transformer) { ::AcaEntities::Atp::Transformers::Cv::Family }
  let(:record) { serializer.parse(xml) }
  let(:transformed) { transformer.transform(record.to_hash(identifier: true)) }
  let(:family_hash) { transformed[:family].to_h.deep_stringify_keys! }

  context 'validation' do
    it 'fails when family hash is blank' do
      result = subject.call(family_hash: nil)
      expect(result).to be_failure
      expect(result.failure).to eq('Family member should not be blank')
    end

    it 'fails when family hash is not a hash' do
      result = subject.call(family_hash: 'not a hash')
      expect(result).to be_failure
      expect(result.failure).to eq('Family member should be a hash')
    end
  end

  context 'family creation' do
    before do
      ::BenefitMarkets::Locations::CountyZip.create(zip: "04330", state: "ME", county_name: "Kennebec")
    end

    it 'creates a new family when one does not exist' do
      result = subject.call({family_hash: family_hash})
      expect(result).to be_success
      expect(result.success).to be_a(::Family)
      expect(Family.count).to eq(1)
    end

    it 'creates family with one primary member' do
      result = subject.call(family_hash: family_hash)
      expect(result).to be_success
      family = result.success
      expect(family.family_members.count).to eq(1)
      expect(family.family_members.first.is_primary_applicant).to be_truthy
    end

    it 'returns existing family when one exists with matching primary person' do
      # First create a family
      first_result = subject.call(family_hash: family_hash)
      expect(first_result).to be_success
      original_family = first_result.success

      # Try to create again with same data
      second_result = subject.call(family_hash: family_hash)
      expect(second_result).to be_success
      expect(second_result.success).to eq(original_family)
      expect(Family.count).to eq(1)
    end

    it 'fails when no primary applicant is found in payload' do
      modified_hash = family_hash.deep_dup
      modified_hash['family_members'].each { |fm| fm["is_primary_applicant"] = false }

      result = subject.call(family_hash: modified_hash)
      expect(result).to be_failure
      expect(result.failure).to eq("No primary applicant found in payload")
    end
  end

  context 'person creation' do
    it 'creates a new person for primary family member' do
      result = subject.call(family_hash: family_hash)
      expect(result).to be_success
      expect(Person.count).to eq(1)
      person = Person.first
      primary_member_hash = family_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      expect(person.first_name).to eq(primary_member_hash['person']['person_name']['first_name'])
      expect(person.last_name).to eq(primary_member_hash['person']['person_name']['last_name'])
    end

    it 'uses existing person when one matches' do
      # First create a person via the operation
      first_result = subject.call(family_hash: family_hash)
      expect(first_result).to be_success
      original_person = Person.first

      # Try to create again with same data
      second_result = subject.call(family_hash: family_hash)
      expect(second_result).to be_success
      expect(Person.count).to eq(1)
      expect(Person.first).to eq(original_person)
    end
  end

  context 'phone handling' do
    let(:invalid_phone_hash) do
      modified_hash = family_hash.deep_dup
      primary_member = modified_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      primary_member['person']['phones'] << {
        "kind" => "home",
        "country_code" => "1",
        "area_code" => "000",
        "number" => "0000000",
        "full_phone_number" => "0000000000",
        "primary" => false
      }
      modified_hash
    end

    it 'filters out invalid phone numbers' do
      result = subject.call(family_hash: invalid_phone_hash)
      expect(result).to be_success
      person = Person.first
      invalid_phone = person.phones.any? do |p|
        p.area_code == '000' || p.full_phone_number == '0000000000'
      end
      expect(invalid_phone).to be_falsey
    end
  end

  context 'consumer role' do
    it 'creates a consumer role for the primary person' do
      result = subject.call(family_hash: family_hash)
      expect(result).to be_success
      person = Person.first
      expect(person.consumer_role).to be_present
    end

    it 'sets citizen status on consumer role' do
      result = subject.call(family_hash: family_hash)
      expect(result).to be_success
      person = Person.first
      primary_member_hash = family_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      expected_status = primary_member_hash['person']['consumer_role']['lawful_presence_determination']['citizen_status']
      expect(person.consumer_role.citizen_status).to eq(expected_status)
    end
  end

  context 'vlp documents' do
    it 'creates vlp documents for the primary person' do
      result = subject.call(family_hash: family_hash)
      expect(result).to be_success
      person = Person.first
      primary_member_hash = family_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      vlp_docs_count = primary_member_hash['person']['consumer_role']['vlp_documents']&.count || 0
      expect(person.consumer_role.vlp_documents.count).to eq(vlp_docs_count) if vlp_docs_count > 0
    end
  end

  context 'tribal information' do
    let(:tribal_info_hash) do
      modified_hash = family_hash.deep_dup
      primary_member = modified_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      primary_member['person']['person_demographics']['indian_tribe_member'] = true
      primary_member['person']['person_demographics']['tribal_name'] = 'Test Tribe'
      primary_member['person']['person_demographics']['tribal_state'] = 'ME'
      primary_member['person']['person_demographics']['tribe_codes'] = ['OT']
      modified_hash
    end

    before do
      allow(EnrollRegistry[:indian_alaskan_tribe_details].feature).to receive(:is_enabled).and_return(true)
    end

    it 'preserves tribal information when present' do
      result = subject.call(family_hash: tribal_info_hash)
      expect(result).to be_success
      person = Person.first
      expect(person.indian_tribe_member).to be_truthy
      expect(person.tribal_name).to eq('Test Tribe')
      expect(person.tribal_state).to eq('ME')
      expect(person.tribe_codes).to eq(['OT'])
    end

    it 'does not overwrite existing tribal information when not present in new data' do
      # First create a person with tribal info
      first_result = subject.call(family_hash: tribal_info_hash)
      expect(first_result).to be_success

      # Modify hash to remove tribal info
      modified_hash = family_hash.deep_dup
      primary_member = modified_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      primary_member['person']['person_demographics'].delete('indian_tribe_member')
      primary_member['person']['person_demographics'].delete('tribal_name')
      primary_member['person']['person_demographics'].delete('tribal_state')
      primary_member['person']['person_demographics'].delete('tribe_codes')

      # Try to update
      second_result = subject.call(family_hash: modified_hash)
      expect(second_result).to be_success

      # Check that tribal info is preserved
      person = Person.first
      expect(person.indian_tribe_member).to be_truthy
      expect(person.tribal_name).to eq('Test Tribe')
      expect(person.tribal_state).to eq('ME')
      expect(person.tribe_codes).to eq(['OT'])
    end
  end

  context 'no_ssn handling' do
    it 'sets no_ssn to 0 when ssn is present' do
      result = subject.call(family_hash: family_hash)
      expect(result).to be_success
      person = Person.first
      primary_member_hash = family_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      has_ssn = primary_member_hash['person']['person_demographics']['ssn'].present?
      expect(person.no_ssn).to eq(has_ssn ? '0' : '1')
    end

    it 'sets no_ssn to 1 when ssn is not present' do
      modified_hash = family_hash.deep_dup
      primary_member = modified_hash['family_members'].find { |fm| fm["is_primary_applicant"] == true }
      primary_member['person']['person_demographics']['ssn'] = nil

      result = subject.call(family_hash: modified_hash)
      expect(result).to be_success
      person = Person.first
      expect(person.no_ssn).to eq('1')
    end
  end

  context 'relationships' do
    it 'creates a self relationship for the primary person' do
      result = subject.call(family_hash: family_hash)
      expect(result).to be_success
      person = Person.first
      self_relationship = person.person_relationships.detect { |rel| rel.kind == 'self' }
      expect(self_relationship).to be_present
      expect(self_relationship.relative_id).to eq(person.id)
    end
  end
end
