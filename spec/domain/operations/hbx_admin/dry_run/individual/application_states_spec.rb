# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::HbxAdmin::DryRun::Individual::ApplicationStates, dbclean: :after_each do

  let!(:hbx_profile) { FactoryBot.create(:hbx_profile) }
  let!(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, hbx_profile: hbx_profile) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member) }

  let!(:benefit_coverage_period_previous_year) do
    FactoryBot.build(:benefit_coverage_period,
                     start_on: (TimeKeeper.date_of_record - 1.year).beginning_of_year,
                     end_on: (TimeKeeper.date_of_record - 1.year).end_of_year,
                     open_enrollment_start_on: ((TimeKeeper.date_of_record - 1.year).beginning_of_year - 2.months),
                     open_enrollment_end_on: ((TimeKeeper.date_of_record - 1.year).beginning_of_year + 1.month))
  end

  let!(:benefit_coverage_period_this_year) do
    FactoryBot.build(:benefit_coverage_period,
                     start_on: TimeKeeper.date_of_record.beginning_of_year,
                     end_on: TimeKeeper.date_of_record.end_of_year,
                     open_enrollment_start_on: (TimeKeeper.date_of_record.beginning_of_year - 2.months),
                     open_enrollment_end_on: (TimeKeeper.date_of_record.beginning_of_year + 1.month))
  end

  let!(:benefit_coverage_period_next_year) do
    FactoryBot.build(:benefit_coverage_period,
                     start_on: (TimeKeeper.date_of_record + 1.year).beginning_of_year,
                     end_on: (TimeKeeper.date_of_record + 1.year).end_of_year,
                     open_enrollment_start_on: ((TimeKeeper.date_of_record + 1.year).beginning_of_year - 2.months),
                     open_enrollment_end_on: ((TimeKeeper.date_of_record + 1.year).beginning_of_year + 1.month))
  end

  let!(:hbx_enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      family: family,
                      kind: "individual",
                      aasm_state: "coverage_selected",
                      effective_on: Date.current.beginning_of_year)
  end

  let!(:application) do
    FactoryBot.create(:financial_assistance_application,
                      family_id: family.id,
                      aasm_state: "determined",
                      assistance_year: (Date.current.year - 1),
                      predecessor_id: nil)
  end

  let!(:renewal_application) do
    FactoryBot.create(:financial_assistance_application,
                      family_id: family.id,
                      aasm_state: "draft",
                      assistance_year: Date.current.year,
                      predecessor_id: application.id,
                      origin: :system,
                      generation_reason: :renewal)
  end

  before do
    benefit_sponsorship.benefit_coverage_periods = []
    benefit_sponsorship.benefit_coverage_periods = [benefit_coverage_period_previous_year, benefit_coverage_period_this_year, benefit_coverage_period_next_year]
    benefit_sponsorship.save!
  end

  describe "#call" do
    context "with valid data" do
      let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }
      let(:benefits_result) { [{}, [2025, 2024, 2023]] }

      before do
        allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
        allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Success(benefits_result))
      end

      it "returns success with expected structure" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        expect(data).to have_key(:eligible_families)
        expect(data).to have_key(:application_states)
        expect(data).to have_key(:renewal_year)
        expect(data[:renewal_year]).to be_a(Integer)
        expect(data[:eligible_families]).to be_a(Hash)
        expect(data[:application_states]).to be_a(Array)
      end

      it "returns eligible families count" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        expect(data[:eligible_families]).to have_key("families_eligible_for_application_renewal")
        expect(data[:eligible_families]["families_eligible_for_application_renewal"]).to be_a(Integer)
      end

      it "returns application states for all coverage years" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        expect(data[:application_states]).to be_an(Array)
        expect(data[:application_states].first).to have_key("assistance_year")
        expect(data[:application_states].first).to have_key("application_states")
      end
    end

    context "when Benefits operation fails" do
      let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }

      before do
        allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
        allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Failure("Benefits operation failed"))
      end

      it "returns failure" do
        result = described_class.new.call

        expect(result).to be_failure
        expect(result.failure).to eq("Failed to get coverage years")
      end
    end
  end

  describe "#fetch_coverage_years" do
    let(:operation) { described_class.new }

    context "when Benefits operation succeeds" do
      let(:benefits_result) { [{}, [2025, 2024, 2023]] }
      let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }

      before do
        allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
        allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Success(benefits_result))
      end

      it "returns coverage years" do
        result = operation.send(:fetch_coverage_years)

        expect(result).to be_success
        expect(result.value!).to eq([2025, 2024, 2023])
      end
    end

    context "when Benefits operation fails" do
      let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }

      before do
        allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
        allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Failure("Benefits failed"))
      end

      it "returns failure with appropriate message" do
        result = operation.send(:fetch_coverage_years)

        expect(result).to be_failure
        expect(result.failure).to eq("Failed to get coverage years")
      end
    end

    context "when an exception occurs" do
      let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }

      before do
        allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
        allow(benefits_operation).to receive(:call).and_raise(StandardError.new("Unexpected error"))
      end

      it "returns failure with error message" do
        result = operation.send(:fetch_coverage_years)

        expect(result).to be_failure
        expect(result.failure).to eq("Coverage years error: Unexpected error")
      end
    end
  end

  describe "#fetch_eligible_families" do
    let(:operation) { described_class.new }
    let(:renewal_year) { Date.current.year }

    context "with eligible families" do
      it "returns count of eligible families" do
        result = operation.send(:fetch_eligible_families, renewal_year)

        expect(result).to be_success
        data = result.value!
        expect(data).to have_key("families_eligible_for_application_renewal")
        expect(data["families_eligible_for_application_renewal"]).to be >= 0
      end
    end

    context "when MongoDB aggregation fails" do
      before do
        allow(::HbxEnrollment).to receive(:collection).and_raise(StandardError.new("Database error"))
      end

      it "returns failure with error message" do
        result = operation.send(:fetch_eligible_families, renewal_year)

        expect(result).to be_failure
        expect(result.failure).to eq("Eligible families error: Database error")
      end
    end
  end

  describe "#fetch_application_states" do
    let(:operation) { described_class.new }
    let(:coverage_years) { [Date.current.year, Date.current.year - 1] }

    context "with valid application states data" do
      it "returns mapped application states for each year" do
        result = operation.send(:fetch_application_states, coverage_years)

        expect(result).to be_success
        data = result.value!

        expect(data).to be_an(Array)
        expect(data.length).to eq(coverage_years.length)

        data.each do |year_data|
          expect(year_data).to have_key("assistance_year")
          expect(year_data).to have_key("application_states")
          expect(year_data["assistance_year"]).to be_in(coverage_years)
          expect(year_data["application_states"]).to be_a(Hash)
        end
      end

      it "includes all application states with zero counts for missing states" do
        result = operation.send(:fetch_application_states, coverage_years)

        expect(result).to be_success
        data = result.value!

        data.each do |year_data|
          application_states = year_data["application_states"]
          ::Operations::HbxAdmin::DryRun::Individual::ApplicationStates::APPLICATION_STATES.each do |state|
            expect(application_states).to have_key(state)
            expect(application_states[state]).to be >= 0
          end
        end
      end
    end

    context "when MongoDB aggregation fails" do
      before do
        allow(::FinancialAssistance::Application).to receive(:collection).and_raise(StandardError.new("Aggregation error"))
      end

      it "returns failure with error message" do
        result = operation.send(:fetch_application_states, coverage_years)

        expect(result).to be_failure
        expect(result.failure).to eq("Application states error: Aggregation error")
      end
    end

    context "with empty coverage years" do
      it "returns empty array for empty coverage years" do
        result = operation.send(:fetch_application_states, [])

        expect(result).to be_success
        expect(result.value!).to eq([])
      end
    end
  end

  describe "integration with real data" do
    let!(:additional_family) { FactoryBot.create(:family, :with_primary_family_member) }
    let!(:additional_application) do
      FactoryBot.create(:financial_assistance_application,
                        family_id: additional_family.id,
                        assistance_year: Date.current.year,
                        aasm_state: "draft",
                        predecessor_id: BSON::ObjectId.new,
                        origin: :system,
                        generation_reason: :renewal)
    end

    let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }
    let(:benefits_result) { [{}, [Date.current.year, Date.current.year - 1]] }

    before do
      allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
      allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Success(benefits_result))
    end

    it "aggregates application states correctly" do
      result = described_class.new.call

      expect(result).to be_success

      data = result.value!
      application_states = data[:application_states]

      # Find the current year data
      current_year_data = application_states.find { |year_data| year_data["assistance_year"] == Date.current.year }
      expect(current_year_data).to be_present

      states = current_year_data["application_states"]
      expect(states["draft"]).to be >= 1  # Our renewal_application and additional_application
    end
  end

end
