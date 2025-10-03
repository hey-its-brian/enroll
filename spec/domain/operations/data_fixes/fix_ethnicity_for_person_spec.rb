# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::DataFixes::FixEthnicityForPerson, type: :model, dbclean: :after_each do
  let(:person) { FactoryBot.create(:person, :with_consumer_role) }

  it 'should be a container-ready operation' do
    expect(subject.respond_to?(:call)).to be_truthy
  end

  context 'with valid hbx_id' do
    context 'when ethnicity is nil' do
      before do
        person.set(ethnicity: nil)
      end

      it 'returns success' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
      end

      it 'sets ethnicity to empty array' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
        person.reload
        expect(person.ethnicity).to eq([])
      end
    end

    context 'when ethnicity has nil values' do
      before do
        person.set(ethnicity: ['Hispanic or Latino', nil, 'Not Hispanic or Latino', nil])
      end

      it 'returns success' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
      end

      it 'removes nil values from ethnicity' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
        person.reload
        expect(person.ethnicity).to eq(['Hispanic or Latino', 'Not Hispanic or Latino'])
      end
    end

    context 'when ethnicity is already clean' do
      before do
        person.set(ethnicity: ['Hispanic or Latino', 'Not Hispanic or Latino'])
      end

      it 'returns success' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
      end

      it 'keeps ethnicity unchanged' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
        person.reload
        expect(person.ethnicity).to eq(['Hispanic or Latino', 'Not Hispanic or Latino'])
      end
    end

    context 'when ethnicity is empty array' do
      before do
        person.set(ethnicity: [])
      end

      it 'returns success' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
      end

      it 'keeps ethnicity as empty array' do
        result = subject.call(person_hbx_id: person.hbx_id)
        expect(result).to be_success
        person.reload
        expect(person.ethnicity).to eq([])
      end
    end
  end

  context 'with invalid hbx_id' do
    before do
      @result = subject.call(person_hbx_id: 'invalid_hbx_id')
    end

    it 'returns failure' do
      expect(@result).to be_failure
    end

    it 'returns application_not_found error' do
      expect(@result.failure).to eq(:person_not_found)
    end
  end
end
