# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family, type: :model do
  after :all do
    DatabaseCleaner.clean
  end

  let(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }

  let(:current_year) { TimeKeeper.date_of_record.year }
  let(:previous_year) { current_year.pred }
  let(:next_year) { current_year.next }

  describe '#fetch_copyable_faa_application_ids' do
    let(:faa_app1) do
      FactoryBot.create(
        :financial_assistance_application,
        aasm_state: 'determined',
        assistance_year: current_year,
        family_id: family.id
      )
    end

    before do
      faa_app1
    end

    context 'when there is only one determined application for a year' do
      it 'returns the application ID for that year' do
        result = family.fetch_copyable_faa_application_ids

        expect(result).to eq([faa_app1.id])
      end
    end

    context 'when there are multiple determined applications for the same year' do
      let(:earlier_app) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'determined',
          assistance_year: current_year,
          family_id: family.id,
          submitted_at: 2.days.ago
        )
      end

      let(:latest_app) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'determined',
          assistance_year: current_year,
          family_id: family.id,
          submitted_at: 1.day.ago
        )
      end

      before do
        earlier_app
        latest_app
      end

      it 'returns only the most recently submitted application ID for each year' do
        result = family.fetch_copyable_faa_application_ids

        expect(result).to eq([latest_app.id])
        expect(result).not_to include(earlier_app.id)
        expect(result.count).to eq(1)
      end
    end

    context 'when there are applications for multiple years' do
      let(:previous_year_app) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'determined',
          assistance_year: previous_year,
          family_id: family.id,
          submitted_at: 3.days.ago
        )
      end

      let(:next_year_app) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'determined',
          assistance_year: next_year,
          family_id: family.id,
          submitted_at: 1.day.ago
        )
      end

      before do
        previous_year_app
        next_year_app
      end

      it 'returns one application ID per year' do
        result = family.fetch_copyable_faa_application_ids

        expect(result).to include(faa_app1.id)
        expect(result).to include(previous_year_app.id)
        expect(result).to include(next_year_app.id)
        expect(result.count).to eq(3)
      end
    end

    context 'when applications have different states' do
      let(:draft_app) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'draft',
          assistance_year: current_year,
          family_id: family.id
        )
      end

      let(:submitted_app) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'submitted',
          assistance_year: next_year,
          family_id: family.id
        )
      end

      before do
        draft_app
        submitted_app
      end

      it 'only returns applications in determined state' do
        result = family.fetch_copyable_faa_application_ids

        expect(result).to include(faa_app1.id)
        expect(result).not_to include(draft_app.id)
        expect(result).not_to include(submitted_app.id)
        expect(result.count).to eq(1)
      end
    end

    context 'when there are no determined applications' do
      before do
        FinancialAssistance::Application.destroy_all
      end

      it 'returns an empty array' do
        result = family.fetch_copyable_faa_application_ids

        expect(result).to be_empty
      end
    end

    context 'when there are determined applications for different families' do
      let(:other_person) { FactoryBot.create(:person, :with_consumer_role) }
      let(:other_family) { FactoryBot.create(:family, :with_primary_family_member, person: other_person) }

      let(:other_family_app) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'determined',
          assistance_year: current_year,
          family_id: other_family.id
        )
      end

      before do
        other_family_app
      end

      it 'only returns applications for the specified family' do
        result = family.fetch_copyable_faa_application_ids

        expect(result).to include(faa_app1.id)
        expect(result).not_to include(other_family_app.id)
        expect(result.count).to eq(1)
      end
    end
  end

  describe '#fetch_copyable_application_ids' do
    context 'with only financial assistance applications' do
      let(:faa_app1) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'determined',
          assistance_year: current_year,
          family_id: family.id
        )
      end

      before do
        faa_app1
      end

      context 'when there is only one determined application for a year' do
        it 'returns the application ID for that year' do
          result = family.fetch_copyable_application_ids

          expect(result).to eq([faa_app1.id])
        end
      end

      context 'when there are multiple determined applications for the same year' do
        let(:earlier_app) do
          FactoryBot.create(
            :financial_assistance_application,
            aasm_state: 'determined',
            assistance_year: current_year,
            family_id: family.id,
            submitted_at: 2.days.ago
          )
        end

        let(:latest_app) do
          FactoryBot.create(
            :financial_assistance_application,
            aasm_state: 'determined',
            assistance_year: current_year,
            family_id: family.id,
            submitted_at: 1.day.ago
          )
        end

        before do
          earlier_app
          latest_app
        end

        it 'returns only the most recently submitted application ID for each year' do
          result = family.fetch_copyable_application_ids

          expect(result).to eq([latest_app.id])
          expect(result).not_to include(earlier_app.id)
          expect(result.count).to eq(1)
        end
      end

      context 'when there are applications for multiple years' do
        let(:previous_year_app) do
          FactoryBot.create(
            :financial_assistance_application,
            aasm_state: 'determined',
            assistance_year: previous_year,
            family_id: family.id,
            submitted_at: 3.days.ago
          )
        end

        let(:next_year_app) do
          FactoryBot.create(
            :financial_assistance_application,
            aasm_state: 'determined',
            assistance_year: next_year,
            family_id: family.id,
            submitted_at: 1.day.ago
          )
        end

        before do
          previous_year_app
          next_year_app
        end

        it 'returns one application ID per year' do
          result = family.fetch_copyable_application_ids

          expect(result).to include(faa_app1.id)
          expect(result).to include(previous_year_app.id)
          expect(result).to include(next_year_app.id)
          expect(result.count).to eq(3)
        end
      end

      context 'when applications have different states' do
        let(:draft_app) do
          FactoryBot.create(
            :financial_assistance_application,
            aasm_state: 'draft',
            assistance_year: current_year,
            family_id: family.id
          )
        end

        let(:submitted_app) do
          FactoryBot.create(
            :financial_assistance_application,
            aasm_state: 'submitted',
            assistance_year: next_year,
            family_id: family.id
          )
        end

        before do
          draft_app
          submitted_app
        end

        it 'only returns applications in determined state' do
          result = family.fetch_copyable_application_ids

          expect(result).to include(faa_app1.id)
          expect(result).not_to include(draft_app.id)
          expect(result).not_to include(submitted_app.id)
          expect(result.count).to eq(1)
        end
      end

      context 'when there are no determined applications' do
        before do
          FinancialAssistance::Application.destroy_all
        end

        it 'returns an empty array' do
          result = family.fetch_copyable_application_ids

          expect(result).to be_empty
        end
      end

      context 'when there are determined applications for different families' do
        let(:other_person) { FactoryBot.create(:person, :with_consumer_role) }
        let(:other_family) { FactoryBot.create(:family, :with_primary_family_member, person: other_person) }

        let(:other_family_app) do
          FactoryBot.create(
            :financial_assistance_application,
            aasm_state: 'determined',
            assistance_year: current_year,
            family_id: other_family.id
          )
        end

        before do
          other_family_app
        end

        it 'only returns applications for the specified family' do
          result = family.fetch_copyable_application_ids

          expect(result).to include(faa_app1.id)
          expect(result).not_to include(other_family_app.id)
          expect(result.count).to eq(1)
        end
      end
    end

    context 'with both financial assistance and individual market applications' do
      let(:qhp_app1) do
        FactoryBot.create(
          :individual_market_application,
          current_state: 'determined',
          assistance_year: qhp_assistance_year,
          submitted_at: qhp_submitted_at,
          family_id: family.id
        )
      end

      let(:faa_app1) do
        FactoryBot.create(
          :financial_assistance_application,
          aasm_state: 'determined',
          assistance_year: faa_assistance_year,
          submitted_at: faa_submitted_at,
          family_id: family.id
        )
      end

      let(:qhp_assistance_year) { current_year }
      let(:faa_assistance_year) { current_year }
      let(:random_submitted_at) { Time.now }
      let(:qhp_submitted_at) { random_submitted_at }
      let(:faa_submitted_at) { random_submitted_at }

      before do
        qhp_app1
        faa_app1
      end

      context 'when both applications are for the same year' do
        let(:qhp_submitted_at) { 1.day.ago }
        let(:faa_submitted_at) { 2.days.ago }

        it 'returns the most recently submitted application IDs for that year one per each type' do
          result = family.fetch_copyable_application_ids

          expect(result).to eq([faa_app1.id, qhp_app1.id])
          expect(result.count).to eq(2)
        end
      end

      context 'when applications are for different years' do
        let(:qhp_assistance_year) { current_year }
        let(:faa_assistance_year) { previous_year }

        it 'returns one application ID for each year' do
          result = family.fetch_copyable_application_ids

          expect(result).to include(qhp_app1.id)
          expect(result).to include(faa_app1.id)
          expect(result.count).to eq(2)
        end
      end
    end
  end
end
