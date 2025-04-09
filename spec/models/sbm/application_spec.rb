# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Sbm::Application, type: :model do
  let(:application) { FactoryBot.create(:sbm_application) }

  describe 'associations' do
    it 'belongs to a family' do
      expect(application.family).to be_a(Family)
    end
  end
end
