# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::FinancialAssistance::Application, type: :model do

  let(:person) { FactoryBot.create(:person, :with_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:application1) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }

  let(:application2) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family.id,
      hbx_id: app_hbx_id
    )
  end

  describe 'hbx_id' do
    before do
      application1
      described_class.remove_indexes
      described_class.create_indexes
    end

    context 'when hbx_id is not unique' do
      let(:app_hbx_id) { application1.hbx_id }

      it 'raises an error' do
        expect { application2 }.to raise_error(
          Mongo::Error::OperationFailure
        ).with_message(
          /E11000 duplicate key error collection/
        )
      end
    end

    context 'when hbx_id is unique' do
      let(:app_hbx_id) { '12345678901234567890' }

      it 'creates a new tax household group' do
        expect(application2).to be_a(described_class)
      end
    end
  end
end
