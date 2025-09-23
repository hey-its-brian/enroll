# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::HbxAdmin::DryRun::Individual::QhpApplicationStates, dbclean: :after_each do

  before :all do
    DatabaseCleaner.clean
  end

  let(:organization) { FactoryBot.create(:organization, :with_office_locations) }
  let(:hbx_profile) { FactoryBot.create(:hbx_profile, organization: organization) }
  let(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, hbx_profile: hbx_profile) }
  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }

  let(:benefit_coverage_period_previous_year) do
    FactoryBot.build(:benefit_coverage_period,
                     start_on: (TimeKeeper.date_of_record - 1.year).beginning_of_year,
                     end_on: (TimeKeeper.date_of_record - 1.year).end_of_year,
                     open_enrollment_start_on: ((TimeKeeper.date_of_record - 1.year).beginning_of_year - 2.months),
                     open_enrollment_end_on: ((TimeKeeper.date_of_record - 1.year).beginning_of_year + 1.month))
  end

  let(:benefit_coverage_period_this_year) do
    FactoryBot.build(:benefit_coverage_period,
                     start_on: TimeKeeper.date_of_record.beginning_of_year,
                     end_on: TimeKeeper.date_of_record.end_of_year,
                     open_enrollment_start_on: (TimeKeeper.date_of_record.beginning_of_year - 2.months),
                     open_enrollment_end_on: (TimeKeeper.date_of_record.beginning_of_year + 1.month))
  end

  let(:benefit_coverage_period_next_year) do
    FactoryBot.build(:benefit_coverage_period,
                     start_on: (TimeKeeper.date_of_record + 1.year).beginning_of_year,
                     end_on: (TimeKeeper.date_of_record + 1.year).end_of_year,
                     open_enrollment_start_on: ((TimeKeeper.date_of_record + 1.year).beginning_of_year - 2.months),
                     open_enrollment_end_on: ((TimeKeeper.date_of_record + 1.year).beginning_of_year + 1.month))
  end

  let(:app1) { FactoryBot.create(:individual_market_application, :with_primary) }
  let(:app2) { FactoryBot.create(:individual_market_application, :with_primary, :initial_renewal) }

  before do
    benefit_sponsorship.benefit_coverage_periods = []
    benefit_sponsorship.benefit_coverage_periods = [benefit_coverage_period_previous_year, benefit_coverage_period_this_year, benefit_coverage_period_next_year]
    organization.save!
    app1
    app2
  end

  describe '#call' do
    it 'returns success with qhp applications information' do
      expect(subject.call.success?).to be_truthy

      data = subject.call.value!
      application_states = data[:application_states]

      current_year_data = application_states.find { |year_data| year_data[:assistance_year] == Date.current.year }
      expect(current_year_data).to be_present
      states = current_year_data[:application_states]
      expect(states[:initial]).to be >= 1

      renewal_year_data = application_states.find { |year_data| year_data[:assistance_year] == Date.current.year.next }
      expect(renewal_year_data).to be_present
      states = renewal_year_data[:application_states]
      expect(states[:initial]).to be >= 1
    end
  end
end
