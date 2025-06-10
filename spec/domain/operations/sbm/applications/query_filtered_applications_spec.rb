# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Sbm::Applications::QueryFilteredApplications, dbclean: :after_each do
  let(:user) { FactoryBot.create(:user) }
  let(:person) { FactoryBot.create(:person, :with_family, user: user) }
  let(:family) { person.primary_family }
  let(:current_year) { TimeKeeper.date_of_record.year }
  let(:previous_year) { current_year - 1 }
  let(:operation) { described_class.new }

  describe '#call' do
    context 'with invalid params' do
      it 'returns failure when family_id is missing' do
        result = operation.call({})
        expect(result).to be_failure
        expect(result.failure.to_h).to have_key(:family_id)
      end
    end

    context 'with valid params' do
      let!(:qhp_app_current) do
        FactoryBot.create(
          :individual_market_application,
          family_id: family.id,
          assistance_year: current_year,
          current_state: "submitted",
          created_at: 1.day.ago
        )
      end

      let!(:qhp_app_determined) do
        FactoryBot.create(
          :individual_market_application,
          family_id: family.id,
          assistance_year: current_year,
          current_state: "determined",
          created_at: 3.days.ago,
          submitted_at: 2.days.ago
        )
      end

      let!(:faa_app_current) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "draft",
          created_at: 2.days.ago
        )
      end

      let!(:faa_app_determined) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: current_year,
          aasm_state: "determined",
          created_at: 10.days.ago,
          submitted_at: 9.days.ago
        )
      end

      let!(:faa_app_previous) do
        FactoryBot.create(
          :financial_assistance_application,
          family_id: family.id,
          assistance_year: previous_year,
          aasm_state: "submitted",
          created_at: 4.days.ago
        )
      end

      it 'returns all applications for the family' do
        result = operation.call(family_id: family.id)
        expect(result).to be_success

        applications = result.value![:applications]
        expect(applications.count).to eq(5)
        expect(applications).to include(qhp_app_current, qhp_app_determined,
                                        faa_app_current, faa_app_determined, faa_app_previous)
      end

      it 'returns filtered applications sorted by creation date' do
        result = operation.call(family_id: family.id)
        filtered_applications = result.value![:filtered_applications]

        expect(filtered_applications.count).to eq(5)
        expect(filtered_applications).to eq([
          qhp_app_current,
          faa_app_current,
          qhp_app_determined,
          faa_app_previous,
          faa_app_determined
        ])
      end

      it 'returns the correct recent determined application hbx_id' do
        result = operation.call(family_id: family.id)
        expect(result.value![:recent_determined_hbx_id]).to eq(qhp_app_determined.hbx_id)
      end

      context 'with year filter' do
        it 'returns only applications for the specified year' do
          result = operation.call(family_id: family.id, filter_year: current_year.to_s)

          applications = result.value![:applications]
          expect(applications.count).to eq(4)
          expect(applications).to include(qhp_app_current, qhp_app_determined,
                                          faa_app_current, faa_app_determined)
          expect(applications).not_to include(faa_app_previous)
        end

        it 'filters and sorts applications correctly for the previous year' do
          result = operation.call(family_id: family.id, filter_year: previous_year.to_s)

          applications = result.value![:applications]
          filtered_applications = result.value![:filtered_applications]

          expect(applications.count).to eq(1)
          expect(applications).to include(faa_app_previous)

          expect(filtered_applications).to eq([faa_app_previous])
        end
      end

      context 'when no determined applications exist' do
        before do
          qhp_app_determined.update_attributes(current_state: "submitted")
          faa_app_determined.update_attributes(aasm_state: "submitted")
        end

        it 'returns nil for recent_determined_hbx_id' do
          result = operation.call(family_id: family.id)
          expect(result.value![:recent_determined_hbx_id]).to be_nil
        end
      end

      context 'with determined applications in different years' do
        let!(:faa_app_determined_newer) do
          FactoryBot.create(
            :financial_assistance_application,
            family_id: family.id,
            assistance_year: current_year + 1,
            aasm_state: "determined",
            created_at: 3.days.ago,
            submitted_at: 2.days.ago
          )
        end

        it 'returns the most recent year determined application hbx_id' do
          result = operation.call(family_id: family.id)
          expect(result.value![:recent_determined_hbx_id]).to eq(faa_app_determined_newer.hbx_id)
        end
      end

      context 'with determined applications in same year but different submission dates' do
        let!(:qhp_app_determined_recent) do
          FactoryBot.create(
            :individual_market_application,
            family_id: family.id,
            assistance_year: current_year,
            current_state: "determined",
            created_at: TimeKeeper.date_of_record,
            submitted_at: 1.day.ago
          )
        end

        it 'returns the most recently submitted application hbx_id' do
          result = operation.call(family_id: family.id)
          expect(result.value![:recent_determined_hbx_id]).to eq(qhp_app_determined_recent.hbx_id)
        end
      end
    end
  end
end
