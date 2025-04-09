# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Relationship, type: :model do
  let(:application) { FactoryBot.create(:individual_market_application) }
  let(:applicant1) { FactoryBot.create(:individual_market_applicant, application: application) }
  let(:applicant2) { FactoryBot.create(:individual_market_applicant, application: application) }
  let(:relationship) do
    FactoryBot.create(
      :individual_market_relationship,
      application: application,
      source_id: applicant1.id,
      relative_id: applicant2.id,
      kind: 'spouse'
    )
  end

  describe 'fields' do
    it { is_expected.to have_field(:kind).of_type(String) }
    it { is_expected.to have_field(:source_id).of_type(BSON::ObjectId) }
    it { is_expected.to have_field(:relative_id).of_type(BSON::ObjectId) }
  end

  describe 'associations' do
    it { is_expected.to be_embedded_in(:application).of_type(IndividualMarket::Application) }

    it 'returns application as the parent' do
      expect(relationship.application).to eq(application)
    end
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:kind) }
    it { is_expected.to validate_inclusion_of(:kind).to_allow(IndividualMarket::Relationship::RELATIONSHIP_KINDS) }
    it { is_expected.to validate_presence_of(:source_id) }
    it { is_expected.to validate_presence_of(:relative_id) }
  end

  describe '#source' do
    it 'returns the source applicant' do
      expect(relationship.source).to eq(applicant1)
    end
  end

  describe '#relative' do
    it 'returns the relative applicant' do
      expect(relationship.relative).to eq(applicant2)
    end
  end

  describe 'valid relationship kinds' do
    it 'allows valid relationship kinds' do
      IndividualMarket::Relationship::RELATIONSHIP_KINDS.each do |kind|
        relationship.kind = kind
        expect(relationship).to be_valid
      end
    end
  end

  describe 'invalid relationship kinds' do
    it 'does not allow invalid relationship kinds' do
      relationship.kind = 'invalid_kind'
      expect(relationship).not_to be_valid
      expect(relationship.errors[:kind]).to include('is not included in the list')
    end
  end

  describe 'edge cases' do
    it 'does not allow source_id to be nil' do
      relationship.source_id = nil
      expect(relationship).not_to be_valid
      expect(relationship.errors[:source_id]).to include("can't be blank")
    end

    it 'does not allow relative_id to be nil' do
      relationship.relative_id = nil
      expect(relationship).not_to be_valid
      expect(relationship.errors[:relative_id]).to include("can't be blank")
    end
  end

  describe 'self-referential relationships' do
    it 'is invalid when source_id and relative_id are the same' do
      invalid_relationship = FactoryBot.build(
        :individual_market_relationship,
        application: application,
        source_id: applicant1.id,
        relative_id: applicant1.id,
        kind: 'spouse'
      )
      expect(invalid_relationship).not_to be_valid
      expect(invalid_relationship.errors[:relative_id]).to include('cannot be the same as source')
    end
  end
end
