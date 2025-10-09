# frozen_string_literal: true

RSpec.describe Operations::Families::ApplyForFinancialAssistance, type: :model, dbclean: :after_each do
  it 'should be a container-ready operation' do
    expect(subject.respond_to?(:call)).to be_truthy
  end

  context 'bad argument' do
    it 'should return failure' do
      expect(subject.call(family_id: 'family_id')).to be_a Dry::Monads::Result::Failure
    end
  end

  context 'with a family' do
    let!(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn) }
    let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

    before do
      @result = subject.call(family_id: family.id)
    end

    it 'should return success' do
      expect(@result).to be_a Dry::Monads::Result::Success
    end

    it 'should match with person hbx_id' do
      expect(@result.success.first[:person_hbx_id]).to eq(person.hbx_id)
    end

    it 'should include relationship' do
      expect(@result.success.first[:relationship]).to eq('self')
    end

    it 'should have all the matching keys' do
      [:person_hbx_id, :is_applying_coverage, :citizen_status, :is_consumer_role,
       :five_year_bar_applies, :five_year_bar_met, :qualified_non_citizen,
       :indian_tribe_member, :is_incarcerated, :addresses, :phones, :emails,
       :family_member_id, :is_primary_applicant].each do |key|
        expect(@result.success.first.keys).to include(key)
      end
    end
  end

  describe 'with address populated with location_state_code' do
    let!(:person10) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn) }
    let!(:family10) { FactoryBot.create(:family, :with_primary_family_member, person: person10) }
    let!(:address10) do
      person10.addresses.destroy_all
      addr = FactoryBot.create(:address, person: person10)
      addr.update_attributes!({ location_state_code: addr.state, full_text: 'full_text' })
      addr
    end

    before do
      @result = subject.call(family_id: family10.id)
      @address = @result.success.first[:addresses].first
    end

    it 'should return success' do
      expect(@result).to be_success
    end

    it 'persisted address should have location_state_code populated' do
      expect(address10.location_state_code).to eq(address10.state)
    end

    it 'persisted address should have full_text populated' do
      expect(address10.full_text).to eq('full_text')
    end

    it 'should not return location_state_code' do
      expect(@address.keys).not_to include(:location_state_code)
    end

    it 'should not return full_text' do
      expect(@address.keys).not_to include(:full_text)
    end

    it 'should include :kind with value' do
      expect(@address[:kind]).not_to be_blank
    end

    it 'should include :address_1 with value' do
      expect(@address[:address_1]).not_to be_blank
    end

    it 'should include :city with value' do
      expect(@address[:city]).not_to be_blank
    end

    it 'should include :county with value' do
      expect(@address[:county]).not_to be_blank
    end

    it 'should include :state with value' do
      expect(@address[:state]).not_to be_blank
    end

    it 'should include :zip with value' do
      expect(@address[:zip]).not_to be_blank
    end
  end

  describe 'with inactive family members' do
    let!(:person11) do
      FactoryBot.create(:person,
                        :with_consumer_role,
                        :with_active_consumer_role,
                        :with_ssn,
                        first_name: 'Person11')
    end
    let!(:family11) { FactoryBot.create(:family, :with_primary_family_member, person: person11) }
    let!(:person12) do
      per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, first_name: 'Person12')
      person11.ensure_relationship_with(per, 'spouse')
      per
    end
    let!(:family_member12) do
      FactoryBot.create(:family_member, is_active: false, person: person12, family: family11)
    end

    before do
      @result = subject.call(family_id: family11.id)
    end

    it 'should return success' do
      expect(@result).to be_success
    end

    it 'response should match the number of active_family_members' do
      expect(@result.success.count).to eq(family11.active_family_members.count)
    end

    it 'should return attributes of active family members only' do
      expect(@result.success.first[:first_name]).to eq(person11.first_name)
    end
  end

  describe 'with inactive family members' do
    let!(:person11) do
      FactoryBot.create(:person,
                        :with_consumer_role,
                        :with_active_consumer_role,
                        :with_ssn,
                        first_name: 'Person11')
    end
    let!(:family11) { FactoryBot.create(:family, :with_primary_family_member, person: person11) }
    let!(:person12) do
      per = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, first_name: 'Person12')
      person11.ensure_relationship_with(per, 'spouse')
      per
    end
    let!(:family_member12) do
      FactoryBot.create(:family_member, person: person12, family: family11)
    end

    before do
      @result = subject.call(family_id: family11.id)
      @member_hashes = @result.success
    end

    it 'should return success' do
      expect(@result).to be_success
    end

    it 'should include relationship key with value' do
      @member_hashes.each do |member_hash|
        expect(member_hash.keys).to include(:relationship)
        expect(member_hash[:relationship]).to be_truthy
      end
    end
  end

  describe 'five year bar information' do
    let!(:person) do
      consumer = FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn)
      consumer.consumer_role.five_year_bar_applies = true
      consumer.consumer_role.five_year_bar_met = true
      consumer.save!
      consumer.consumer_role.lawful_presence_determination.update!(qualified_non_citizenship_result: 'N')
      consumer
    end
    let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

    before do
      @result = subject.call(family_id: family.id)
    end

    it 'should match with person hbx_id' do
      expect(@result.success.first[:five_year_bar_applies]).to eq(person.consumer_role.five_year_bar_applies)
      expect(@result.success.first[:five_year_bar_met]).to eq(person.consumer_role.five_year_bar_met)
      expect(@result.success.first[:qualified_non_citizen]).to eq(false)
    end
  end

  describe 'qualified non citizen information' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

    it "qualified_non_citizenship_result is 'N'" do
      person.consumer_role.lawful_presence_determination.update!(qualified_non_citizenship_result: 'N')
      result = subject.call(family_id: family.id)
      expect(result.success.first[:qualified_non_citizen]).to eq(false)
    end

    it "qualified_non_citizenship_result is 'Y'" do
      person.consumer_role.lawful_presence_determination.update!(qualified_non_citizenship_result: 'Y')
      result = subject.call(family_id: family.id)
      expect(result.success.first[:qualified_non_citizen]).to eq(true)
    end

    it "qualified_non_citizenship_result is nil" do
      person.consumer_role.lawful_presence_determination.update!(qualified_non_citizenship_result: nil)
      result = subject.call(family_id: family.id)
      expect(result.success.first[:qualified_non_citizen]).to eq(nil)
    end

    context 'qualified_non_citizenship_result is nil' do
      it 'returns true if person is a alien_lawfully_present' do
        person.consumer_role.update!(citizen_status: 'alien_lawfully_present')
        result = subject.call(family_id: family.id)
        expect(result.success.first[:qualified_non_citizen]).to eq(true)
      end

      it 'returns nil if person is a us_citizen' do
        person.consumer_role.update!(citizen_status: 'us_citizen')
        result = subject.call(family_id: family.id)
        expect(result.success.first[:qualified_non_citizen]).to eq(nil)
      end
    end
  end

  describe 'contact_method information' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, :with_ssn) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

    it "return contact method information from consumer_role" do
      person.consumer_role.update!(contact_method: 'Paper, Electronic and Text Message communications')
      result = subject.call(family_id: family.id)
      expect(result.success.first[:contact_method]).to eq('Paper, Electronic and Text Message communications')
    end
  end

  describe 'active vlp fields' do
    let(:document) { FactoryBot.build(:vlp_document, **doc_attrs) }
    let(:consumer_role) { FactoryBot.create(:consumer_role, vlp_documents: [document], active_vlp_document_id: document.id) }
    let(:person) { FactoryBot.create(:person, consumer_role: consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

    shared_examples 'includes vlp fields in response' do
      it 'should include all vlp fields in the response' do
        result = subject.call(family_id: family.id).success.first
        doc_attrs.each_key do |key|
          response_key = key == :subject ? :vlp_subject : key
          response_key = key == :description ? :vlp_description : response_key
          value = doc_attrs[key]
          value = value.strftime("%d/%m/%Y") if response_key == :expiration_date
          expect(result[response_key]).to eq(value)
        end
      end
    end

    context 'when consumer has a permanent resident card (I-551)' do
      let(:doc_attrs) do
        {
          subject: 'I-551 (Permanent Resident Card)',
          alien_number: '123456789',
          card_number: '1234567890123',
          expiration_date: Date.current + 1.year
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has employment authorization document (I-766)' do
      let(:doc_attrs) do
        {
          subject: 'I-766 (Employment Authorization Card)',
          alien_number: '987654321',
          card_number: '9876543210987',
          expiration_date: Date.current + 2.years
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has machine readable immigrant visa' do
      let(:doc_attrs) do
        {
          subject: 'Machine Readable Immigrant Visa (with Temporary I-551 Language)',
          alien_number: '555666777',
          passport_number: 'MRV12345678',
          visa_number: 'VISA98765432',
          expiration_date: Date.current + 1.year,
          country_of_citizenship: 'Mexico'
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has I-94 arrival/departure record' do
      let(:doc_attrs) do
        {
          subject: 'I-94 (Arrival/Departure Record)',
          i94_number: '94123456789',
          sevis_id: 'SEVIS12345',
          expiration_date: Date.current + 6.months
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has I-94 in unexpired foreign passport' do
      let(:doc_attrs) do
        {
          subject: 'I-94 (Arrival/Departure Record) in Unexpired Foreign Passport',
          i94_number: '94987654321',
          passport_number: 'P123456789',
          visa_number: '555666777',
          sevis_id: 'SEVIS67890',
          expiration_date: Date.current + 1.year,
          country_of_citizenship: 'Canada'
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has I-20 student certificate' do
      let(:doc_attrs) do
        {
          subject: 'I-20 (Certificate of Eligibility for Nonimmigrant (F-1) Student Status)',
          sevis_id: 'SEVIS11111',
          i94_number: '94555666777',
          passport_number: 'P987654321',
          expiration_date: Date.current + 4.years,
          country_of_citizenship: 'India'
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has I-327 reentry permit' do
      let(:doc_attrs) do
        {
          subject: 'I-327 (Reentry Permit)',
          alien_number: '111222333',
          expiration_date: Date.current + 2.years
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has I-571 refugee travel document' do
      let(:doc_attrs) do
        {
          subject: 'I-571 (Refugee Travel Document)',
          alien_number: '444555666',
          expiration_date: Date.current + 1.year
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has other document with I-94 number' do
      let(:doc_attrs) do
        {
          subject: 'Other (With I-94 Number)',
          i94_number: 'I94OTHER123',
          passport_number: 'P111222333',
          sevis_id: 'SEVIS99999',
          expiration_date: Date.current + 1.year,
          country_of_citizenship: 'Philippines',
          description: 'Special temporary status document'
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end

    context 'when consumer has other document with alien number' do
      let(:doc_attrs) do
        {
          subject: 'Other (With Alien Number)',
          alien_number: '777888999',
          passport_number: 'P444555666',
          sevis_id: 'SEVIS77777',
          expiration_date: Date.current + 1.year,
          country_of_citizenship: 'South Korea',
          description: 'Humanitarian parole document'
        }
      end
      it_behaves_like 'includes vlp fields in response'
    end
  end
end
