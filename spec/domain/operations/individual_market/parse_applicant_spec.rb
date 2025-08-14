# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::IndividualMarket::ParseApplicant, dbclean: :after_each do
  subject { described_class.new }

  describe '#call' do
    context 'with invalid params' do
      context 'when family_member is not provided' do
        let(:params) { {} }

        it 'returns failure' do
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('Given family member is not a valid object')
        end
      end

      context 'when building person params fails' do
        let(:person) { instance_double(Person, id: 'person_id') }
        let(:family_member) { instance_double(::FamilyMember, id: 'family_member_id', person: person) }
        let(:params) { { family_member: family_member } }

        before do
          allow(person).to receive(:middle_name).and_raise(NoMethodError)
        end

        it 'returns failure with appropriate message' do
          result = subject.call(params)
          expect(result).to be_failure
          expect(result.failure).to eq('Given family member is not a valid object')
        end
      end
    end

    context 'with valid params' do
      let!(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role, ethnicity: ['Mexican', 'White']) }
      let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
      let!(:family_member) { family.family_members[0] }
      let!(:person2) do
        per = FactoryBot.create(:person, :with_consumer_role, dob: Date.today - 30.years)
        person.ensure_relationship_with(per, 'spouse')
        per.addresses.delete_all
        person.save!
        per
      end
      let!(:dependent) { FactoryBot.create(:family_member, family: family, person: person2) }

      let!(:result)  { subject.call({family_member: family_member}) }

      it 'returns success' do
        expect(result).to be_success
      end

      it 'should return applicant hash' do
        expect(result.success.is_a?(Hash)).to be_truthy
      end

      it 'returns person name attributes' do
        expect(result.success.keys).to include :person_name
      end

      it 'returns demographics attributes' do
        expect(result.success.keys).to include :demographics
      end

      it 'returns correct eligibilities' do
        expect(result.success.keys).to include :eligibilities
      end

      it 'returns correct top-level attributes' do
        applicant = result.success

        expect(applicant).to include(
          family_member_id: family_member.id,
          is_primary_applicant: true,
          is_applying_coverage: true
        )
      end

      it 'should return hash with is_homeless' do
        expect(result.success[:is_homeless]).to eq person.is_homeless
      end

      it 'should return hash with age_off_excluded' do
        expect(result.success[:age_off_excluded]).to eq person.age_off_excluded
      end

      it 'should have same contact method' do
        expect(result.success[:contact_method]).to eq person.consumer_role.contact_method
      end

      it 'should have same language preference' do
        expect(result.success[:language_preference]).to eq person.consumer_role.language_preference
      end

      it 'should have the same phone numbers' do
        expect(result.success[:phones].count).to eq person.phones.count
        expect(result.success[:phones].first[:kind]).to eq person.phones.first.kind
        expect(result.success[:phones].first[:number]).to eq person.phones.first.number
      end

      it 'should have the same email' do
        expect(result.success[:emails].count).to eq person.emails.count
        expect(result.success[:emails].first[:kind]).to eq person.emails.first.kind
        expect(result.success[:emails].first[:address]).to eq person.emails.first.address
      end

      it 'splits race and ethnicity' do
        expect(result.success[:demographics][:race]).to eq ['White']
        expect(result.success[:demographics][:ethnicity]).to eq ['Mexican']
      end

      context 'when family member is not primary applicant' do
        context "when there is no home address" do
          it 'should return address_same_as_primary as false' do
            result = subject.call({family_member: dependent})
            expect(result.success[:address_same_as_primary]).to be_falsey
          end
        end

        context "when there is same home address as primary" do
          it 'should return address_same_as_primary as true' do
            dependent.person.addresses << Address.new(family_member.person.home_address.attributes.slice("kind", "city", "county", "state", "zip", "address_1", "address_2"))
            dependent.person.save!
            result = subject.call({family_member: dependent})
            expect(result.success[:address_same_as_primary]).to be_truthy
          end
        end

        context "when there is same home address as primary, but is_temporarily_out_of_state is true" do
          it 'should return address_same_as_primary as false' do
            dependent.person.addresses << Address.new(family_member.person.home_address.attributes.slice("kind", "city", "county", "state", "zip", "address_1", "address_2"))
            dependent.person.save!
            dependent.person.update_attributes(is_temporarily_out_of_state: true)
            result = subject.call({family_member: dependent})
            expect(result.success[:address_same_as_primary]).to be_falsey
          end
        end
      end
    end
  end
end
