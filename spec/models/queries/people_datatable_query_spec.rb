# frozen_string_literal: true

require 'rails_helper'

describe Queries::PeopleDatatableQuery, dbclean: :after_each do
  let!(:person1) { FactoryBot.create(:person, :with_consumer_role, first_name: 'Jack', last_name: 'Doe') }
  let!(:person2) { FactoryBot.create(:person, :with_consumer_role, first_name: 'Jane', last_name: 'Smith') }

  subject { described_class.new({}) }

  describe '#datatable_search' do
    it 'sets the search_string' do
      query = subject.datatable_search('John')
      expect(query.search_string).to eq('John')
    end
  end

  describe '#build_scope' do
    context 'when search string is blank' do
      it 'returns all persons' do
        expect(subject.build_scope).to eq Person
      end
    end

    context 'when searching with a valid string' do
      it 'returns the correct person records' do
        allow(Person).to receive(:collection).and_return(double(aggregate: [{"_id" => person2.id}]))
        result = subject.build_people_id_criteria('Jane')
        expect(result).to include(person2.id)
      end
    end
  end

  describe '#build_people_id_criteria' do
    context 'when search string contains alphabets' do
      it 'returns person ids matching the text search' do
        allow(Person).to receive(:collection).and_return(double(aggregate: [{"_id" => person1.id}]))
        result = subject.build_people_id_criteria('Jack')
        expect(result).to include(person1.id)
      end
    end

    context 'when search string contains only numbers' do
      it 'returns person ids matching numerical search' do
        result = subject.build_people_id_criteria(person1.hbx_id.to_s)
        expect(result).to include(person1.id)
      end
    end
  end

  describe '#order_by' do
    it 'sets the order_by instance variable' do
      subject.order_by('first_name')
      expect(subject.instance_variable_get(:@order_by)).to eq('first_name')
    end
  end

  describe '#size' do
    it 'returns the count of records in scope' do
      expect(subject.size).to eq(2)
    end
  end
end
