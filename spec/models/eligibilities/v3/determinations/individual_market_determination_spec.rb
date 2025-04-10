# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Eligibilities::V3::Determinations::IndividualMarketDetermination, type: :model do
  let(:applicant)   { FactoryBot.create(:individual_market_applicant, :dependent) }
  let(:eligibility) { FactoryBot.create(:individual_market_eligibility, eligible: applicant) }
  let(:determination) { FactoryBot.create(:individual_market_determination, eligibility: eligibility) }

  describe 'associations' do
    it 'is embedded in eligibility' do
      expect(determination.eligibility).to be_a(Eligibilities::V3::Eligibility)
    end

    it 'embeds many bases' do
      expect(determination.bases).to all(be_a(Eligibilities::V3::Basis))
    end
  end
end
