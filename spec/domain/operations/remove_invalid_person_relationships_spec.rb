# frozen_string_literal: true

require 'rails_helper'
require 'csv'

RSpec.describe Operations::RemoveInvalidPersonRelationships, type: :model, dbclean: :after_each do
  let!(:person_with_valid_rel) { FactoryBot.create(:person) }
  let!(:valid_relative) { FactoryBot.create(:person) }
  let!(:person_with_invalid_rel) { FactoryBot.create(:person) }
  let(:invalid_rel_id) { BSON::ObjectId.new }

  before do
    person_with_valid_rel.person_relationships.create!(relative_id: valid_relative.id, kind: 'spouse')
    person_with_invalid_rel.person_relationships.create!(relative_id: invalid_rel_id, kind: 'child')
  end

  let(:today) { TimeKeeper.date_of_record }

  subject(:operation) { described_class.new }

  before do
    allow(TimeKeeper).to receive(:date_of_record).and_return(today)
  end

  describe '#fetch_invalid_person_relationships' do
    it 'returns a Success with only the invalid relationship data' do
      result = operation.send(:fetch_invalid_person_relationships)
      expect(result).to be_a(Dry::Monads::Result::Success)

      invalid_data = result.value!.to_a
      expect(invalid_data.count).to eq(1)

      invalid_entry = invalid_data.first
      expect(invalid_entry[:person_id]).to eq(person_with_invalid_rel.id)
      expect(invalid_entry[:invalid_relationship][:relative_id]).to eq(invalid_rel_id)
    end
  end

  describe '#process_invalid_relationships' do
    let(:fetched_data) { operation.send(:fetch_invalid_person_relationships).value! }

    context 'when processing valid data' do
      it 'removes the invalid relationship from the person' do
        expect(person_with_invalid_rel.person_relationships.count).to eq(1)
        operation.send(:process_invalid_relationships, fetched_data)
        person_with_invalid_rel.reload
        expect(person_with_invalid_rel.person_relationships.count).to eq(0)
      end

      it 'writes the correct data to the CSV file' do
        operation.call({})
        date = TimeKeeper.date_of_record.strftime("%Y_%m_%d")
        filename = Rails.root.join("removed_invalid_person_relationships_#{date}.csv")
        csv_content = CSV.parse(File.read(filename))

        expect(csv_content[0]).to eq(['Primary Person Hbx Id', 'Invalid Relationship Kind', 'Invalid Relative Id', 'Created At'])
        expect(csv_content[1][0]).to eq(person_with_invalid_rel.hbx_id)
        expect(csv_content[1][1]).to eq('child')
        expect(csv_content[1][2]).to eq(invalid_rel_id.to_s)
      end

      it 'returns a success message with the correct count' do
        result = operation.send(:process_invalid_relationships, fetched_data)
        expect(result).to be_a(Dry::Monads::Result::Success)
        expect(result.value!).to include("Successfully removed 1 invalid relationships")
      end
    end

  end

  describe '#call' do
    it 'returns success' do
      expect(person_with_invalid_rel.person_relationships.count).to eq(1)

      result = operation.call({})

      expect(result).to be_a(Dry::Monads::Result::Success)
      expect(result.value!).to include("Successfully removed 1 invalid relationships")

      person_with_invalid_rel.reload
      expect(person_with_invalid_rel.person_relationships.count).to eq(0)
    end
  end
end