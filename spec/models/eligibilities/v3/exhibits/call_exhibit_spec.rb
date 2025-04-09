# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Exhibits::CallExhibit, type: :model do
  let(:applicant) { FactoryBot.create(:individual_market_applicant) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, :with_evidence, eligible: applicant) }
  let(:evidence) { ivl_eligibility.evidences.first }
  let(:exhibit) { FactoryBot.create(:call_exhibit, :with_document, evidence: evidence) }
  let(:state_history) { FactoryBot.create(:v3_state_history, status_trackable: exhibit) }

  describe 'Model attributes and constants' do
    it { is_expected.to be_mongoid_document }
    it { is_expected.to have_timestamps }
  end

  describe 'STI class' do
    it 'is a subclass of Exhibit' do
      expect(exhibit.class).to eq(described_class)
      expect(described_class.superclass).to eq(Eligibilities::V3::Exhibit)
    end
  end

  describe 'Associations' do
    it { is_expected.to be_embedded_in(:evidence).of_type(Eligibilities::V3::Evidence) }

    it 'embeds many state_histories' do
      expect(described_class).to embed_many(:state_histories).of_type(Eligibilities::V3::StateHistory)
    end

    it 'embeds many documents' do
      expect(described_class).to embed_many(:documents).of_type(Document)
    end
  end

  describe 'Modules' do
    it 'includes HasDocument module' do
      expect(described_class.ancestors).to include(HasDocument)
    end
  end

  describe 'Document functionality' do
    it 'returns document object' do
      expect(exhibit.documents.first).to be_a(Document)
    end
  end

  describe 'State history' do
    it 'returns state history object' do
      expect(state_history).to be_a(Eligibilities::V3::StateHistory)
    end

    context '#latest_state_history' do
      let(:state_history2) { FactoryBot.create(:v3_state_history, status_trackable: exhibit, created_at: Date.current - 1.day) }
      let(:state_history3) { FactoryBot.create(:v3_state_history, status_trackable: exhibit, created_at: Date.current - 2.days) }

      before do
        state_history
        state_history2
        state_history3
      end

      it 'returns the most recent state history record' do
        expect(exhibit.latest_state_history).to eq(state_history)
      end
    end
  end
end
