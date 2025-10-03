# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::DataFixes::RemoveInvalidPersonRelationships, dbclean: :after_each do
  let!(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  let!(:valid_relative) { FactoryBot.create(:person) }
  let!(:valid_relationship) do
    person.person_relationships.create!(relative_id: valid_relative.id, kind: 'spouse')
  end

  let!(:invalid_relative_id) { BSON::ObjectId.new }
  let!(:invalid_relationship) do
    person.person_relationships.create!(relative_id: invalid_relative_id, kind: 'child')
  end

  let(:params) { { person_hbx_id: person.hbx_id } }

  describe 'when invalid relationships exist' do
    it 'removes only invalid relationships and does not trigger person callbacks' do
      person.reload
      expect(person.person_relationships.count).to eq(2)

      expect(person).not_to receive(:person_create_or_update_handler)
      expect(person).not_to receive(:generate_person_saved_event)
      expect(person).not_to receive(:publish_updated_event)

      result = described_class.new.call(params)

      expect(result).to be_success
      person.reload

      remaining_relative_ids = person.person_relationships.map(&:relative_id)
      expect(remaining_relative_ids).to include(valid_relative.id)
      expect(remaining_relative_ids).not_to include(invalid_relative_id)
      expect(person.person_relationships.count).to eq(1)
    end
  end

  describe 'when no invalid relationships exist' do
    it 'returns a success without changes' do
      described_class.new.call(params)
      person.reload
      expect(person.person_relationships.count).to eq(1)

      result = described_class.new.call(params)
      expect(result).to be_success
    end
  end
end



