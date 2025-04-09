# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IndividualMarket::Application, type: :model do
  let(:application) { FactoryBot.create(:individual_market_application) }

  describe 'associations' do
    it 'belongs to a family' do
      expect(application.family).to be_a(Family)
    end

    context 'when creating' do
      it 'sets the _type field correctly' do
        expect(application._type).to eq('IndividualMarket::Application')
      end

      it 'is an instance of IndividualMarket::Application' do
        application
        expect(Sbm::Application.first).to be_a(IndividualMarket::Application)
      end

      it 'is an instance of Sbm::Application' do
        application
        expect(Sbm::Application.first).to be_a(Sbm::Application)
      end
    end
  end

  describe 'validations' do
    describe '#no_duplicate_relationships' do
      let(:applicant1) { FactoryBot.build(:individual_market_applicant, id: BSON::ObjectId.new) }
      let(:applicant2) { FactoryBot.build(:individual_market_applicant, id: BSON::ObjectId.new) }
      let(:relationship1) { FactoryBot.build(:individual_market_relationship, source_id: applicant1.id, relative_id: applicant2.id, kind: 'spouse') }

      before do
        application.applicants = [applicant1, applicant2]
      end

      context 'when there are no duplicate relationships' do
        it 'is valid' do
          application.relationships = [relationship1]
          expect(application.valid?).to be true
        end
      end

      context 'when there are duplicate relationships' do
        let(:relationship2) { FactoryBot.build(:individual_market_relationship, source_id: applicant1.id, relative_id: applicant2.id, kind: 'child') }

        it 'is invalid' do
          application.relationships = [relationship1, relationship2]
          expect(application.valid?).to be false
        end

        it 'adds an error message' do
          application.relationships = [relationship1, relationship2]
          application.valid?
          expect(application.errors[:relationships]).to include('contains duplicate relationships (same source and relative)')
        end
      end

      context 'when relationships have different source and relative pairs' do
        let(:relationship2) { FactoryBot.build(:individual_market_relationship, source_id: applicant2.id, relative_id: applicant1.id, kind: 'parent') }

        it 'is valid' do
          application.relationships = [relationship1, relationship2]
          expect(application.valid?).to be true
        end
      end
    end
  end
end
