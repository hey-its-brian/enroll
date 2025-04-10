# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Exhibit, type: :model do
  let(:applicant) { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:ivl_eligibility) { FactoryBot.create(:individual_market_eligibility, :with_evidence, eligible: applicant) }
  let(:evidence) { ivl_eligibility.evidences.first }
  let(:exhibit) { FactoryBot.create(:v3_exhibit, :with_document, evidence: evidence) }

  describe 'Model attributes and constants' do
    it { is_expected.to be_mongoid_document }
    it { is_expected.to have_timestamps }
  end

  describe 'Associations' do
    it { is_expected.to be_embedded_in(:evidence).of_type(Eligibilities::V3::Evidence) }

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
end
