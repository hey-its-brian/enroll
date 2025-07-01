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

  let(:faa_application) { FactoryBot.create(:financial_assistance_application, family_id: family.id) }
  let(:application) { faa_application }
  let(:qhp_application) { FactoryBot.create(:individual_market_application, family_id: family.id) }

  let(:enabled) { false }
  before :each do
    allow(EnrollRegistry).to receive(:feature_enabled?).with(:qhp_application).and_return(enabled)
  end

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
    context 'with valid application_hbx_id' do
      before do
        current_tax_household_group.set(application_hbx_id: application.hbx_id)
      end

      it 'returns expected application' do
        expect(current_tax_household_group.application).to eq(application)
      end
    end

    context 'without an application for the application_hbx_id' do
      before do
        current_tax_household_group.set(application_hbx_id: '12345')
      end

      it 'returns nil' do
        expect(current_tax_household_group.application).to be_nil
      end
    end

    context 'without an application_hbx_id' do
      it 'returns nil' do
        expect(current_tax_household_group.application).to be_nil
      end
    end

    context 'when qhp_application_feature_enabled is true' do
      let(:enabled) { true }

      context 'with application_gid' do
        context 'when application_gid belongs to a FinancialAssistance::Application' do
          before do
            current_tax_household_group.set(application_gid: faa_application.to_global_id.to_s)
          end

          it 'returns the FinancialAssistance::Application' do
            expect(current_tax_household_group.application).to eq(faa_application)
          end
        end

        context 'when application_gid belongs to an IndividualMarket::Application' do
          before do
            current_tax_household_group.set(application_gid: qhp_application.to_global_id.to_s)
          end

          it 'returns the IndividualMarket::Application' do
            expect(current_tax_household_group.application).to eq(qhp_application)
          end
        end
      end

      context 'without application_gid' do
        context 'when application_hbx_id is present' do
          before do
            current_tax_household_group.set(application_hbx_id: faa_application.hbx_id)
          end

          it 'returns nil' do
            expect(current_tax_household_group.application).to be_nil
          end
        end

        context 'when application_hbx_id is not present' do
          it 'returns nil' do
            expect(current_tax_household_group.application).to be_nil
          end
        end
      end
    end
  end

  describe '#application_type' do
    let(:enabled) { true }

    context 'when application_gid is populated with FinancialAssistance::Application' do
      it 'returns "faa"' do
        current_tax_household_group.set(application_gid: faa_application.to_global_id.to_s)

        expect(current_tax_household_group.application_type).to eq('faa')
      end
    end

    context 'when application_gid is populated with IndividualMarket::Application' do
      it 'returns "qhp"' do
        current_tax_household_group.set(application_gid: qhp_application.to_global_id.to_s)

        expect(current_tax_household_group.application_type).to eq('qhp')
      end
    end

    context 'when application_gid is not populated' do
      it 'returns nil' do
        current_tax_household_group.set(application_gid: nil)

        expect(current_tax_household_group.application_type).to be_nil
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
