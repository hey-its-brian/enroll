# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxHouseholdGroup, type: :model do
  before :all do
    DatabaseCleaner.clean
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let(:system_date) { TimeKeeper.date_of_record }
  let(:retro_tax_household_group) { FactoryBot.create(:tax_household_group, :active_previous_year, family: family) }
  let(:current_tax_household_group) { FactoryBot.create(:tax_household_group, :active_current_year, family: family) }
  let(:prospective_tax_household_group) { FactoryBot.create(:tax_household_group, :active_next_year, family: family) }

  describe '.current_and_prospective_by_year' do
    context 'with retro, current and prospective year thhgs' do
      before do
        retro_tax_household_group
        current_tax_household_group
        prospective_tax_household_group
      end

      it 'returns current and prospective tax household groups' do
        result_thhg_ids = family.tax_household_groups.current_and_prospective_by_year(system_date.year).pluck(:id)
        expect(result_thhg_ids).to include(current_tax_household_group.id, prospective_tax_household_group.id)
        expect(result_thhg_ids).not_to include(retro_tax_household_group.id)
      end
    end
  end

  describe '#application' do
    let(:application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }

    context 'with valid application_hbx_id' do
      before do
        current_tax_household_group.set(application_hbx_id: application.hbx_id)
      end

      it 'returns expected application' do
        expect(current_tax_household_group.application).to eq(application)
      end
    end

    context 'without an application for the applcation_hbx_id' do
      before do
        current_tax_household_group.set(application_hbx_id: '12345')
      end

      it 'returns nil' do
        expect(current_tax_household_group.application).to be_nil
      end
    end

    context 'without an applcation_hbx_id' do
      it 'returns nil' do
        expect(current_tax_household_group.application).to be_nil
      end
    end
  end

  describe 'duplicate hbx_id' do
    let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
    let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
    let(:thhg1) { FactoryBot.create(:tax_household_group, family: family, source: 'Admin') }
    let(:thhg2) { FactoryBot.create(:tax_household_group, family: family, source: 'Admin', hbx_id: thhg_hbx_id) }

    before { thhg1 }

    context 'when hbx_id is not unique' do
      let(:thhg_hbx_id) { thhg1.hbx_id }

      it 'raises an error' do
        expect { thhg2 }.to raise_error(
          Mongoid::Errors::Validations
        ).with_message(
          /HBX ID must be unique/
        )
      end
    end

    context 'when hbx_id is unique' do
      let(:thhg_hbx_id) { '12345678901234567890' }

      it 'creates a new tax household group' do
        expect(thhg2).to be_a(TaxHouseholdGroup)
      end
    end
  end
end
