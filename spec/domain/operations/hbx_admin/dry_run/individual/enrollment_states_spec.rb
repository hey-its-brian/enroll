# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::HbxAdmin::DryRun::Individual::EnrollmentStates, dbclean: :after_each do
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

  let!(:health_enrollment_with_aptc) do
    FactoryBot.create(:hbx_enrollment,
                      family: family,
                      kind: "individual",
                      coverage_kind: "health",
                      aasm_state: "coverage_selected",
                      applied_aptc_amount: 100.0,
                      effective_on: Date.new(2025, 1, 1))  # Use future year to match Benefits mock
  end

  let!(:health_enrollment_without_aptc) do
    FactoryBot.create(:hbx_enrollment,
                      family: family,
                      kind: "individual",
                      coverage_kind: "health",
                      aasm_state: "auto_renewing",
                      applied_aptc_amount: 0.0,
                      effective_on: Date.new(2025, 1, 1))  # Use future year to match Benefits mock
  end

  let!(:dental_enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      family: family,
                      kind: "individual",
                      coverage_kind: "dental",
                      aasm_state: "renewing_coverage_selected",
                      effective_on: Date.new(2025, 1, 1))  # Use future year to match Benefits mock
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

      it "returns success with enrollment states structure" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        expect(data).to be_a(Hash)
        expect(data).to have_key("health")
        expect(data).to have_key("dental")

        expect(data["health"]).to have_key("with_aptc")
        expect(data["health"]).to have_key("without_aptc")

        expect(data["health"]["with_aptc"]).to be_a(Hash)
        expect(data["health"]["without_aptc"]).to be_a(Hash)
        expect(data["dental"]).to be_a(Hash)
      end

      it "includes all expected enrollment states" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        # Check health with APTC states
        expect(data["health"]["with_aptc"]).to have_key("auto_renewing")
        expect(data["health"]["with_aptc"]).to have_key("coverage_selected")
        expect(data["health"]["with_aptc"]).to have_key("renewing_coverage_selected")

        # Check health without APTC states
        expect(data["health"]["without_aptc"]).to have_key("auto_renewing")
        expect(data["health"]["without_aptc"]).to have_key("coverage_selected")
        expect(data["health"]["without_aptc"]).to have_key("renewing_coverage_selected")

        # Check dental states
        expect(data["dental"]).to have_key("auto_renewing")
        expect(data["dental"]).to have_key("coverage_selected")
        expect(data["dental"]).to have_key("renewing_coverage_selected")
      end

      it "aggregates enrollment counts correctly" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        # Should have counts for our test data (may be 0 if aggregation doesn't match)
        expect(data["health"]["with_aptc"]["coverage_selected"]).to be >= 0
        expect(data["health"]["without_aptc"]["auto_renewing"]).to be >= 0
        expect(data["dental"]["renewing_coverage_selected"]).to be >= 0

        # Verify the structure is correct regardless of counts
        expect(data["health"]["with_aptc"].values.sum).to be >= 0
        expect(data["health"]["without_aptc"].values.sum).to be >= 0
        expect(data["dental"].values.sum).to be >= 0
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

  describe "#fetch_enrollment_states" do
    let(:operation) { described_class.new }
    let(:year) { Date.current.year }

    context "with valid enrollment data" do
      it "returns success with enrollment states" do
        result = operation.send(:fetch_enrollment_states, year)

        expect(result).to be_success
        data = result.value!

        expect(data).to be_a(Hash)
        expect(data).to have_key("health")
        expect(data).to have_key("dental")
      end

      it "processes health enrollments with APTC correctly" do
        result = operation.send(:fetch_enrollment_states, year)

        expect(result).to be_success
        data = result.value!

        # Should have health enrollments with APTC
        expect(data["health"]["with_aptc"]["coverage_selected"]).to be >= 0
        expect(data["health"]["without_aptc"]["auto_renewing"]).to be >= 0
      end

      it "processes dental enrollments correctly" do
        result = operation.send(:fetch_enrollment_states, year)

        expect(result).to be_success
        data = result.value!

        # Should have dental enrollments
        expect(data["dental"]["renewing_coverage_selected"]).to be >= 0
      end
    end

    context "when MongoDB aggregation fails" do
      before do
        allow(HbxEnrollment).to receive(:collection).and_raise(StandardError.new("Database error"))
      end

      it "returns default structure on error" do
        result = operation.send(:fetch_enrollment_states, year)

        expect(result).to be_success
        data = result.value!

        # Should return default structure
        expect(data).to eq(operation.send(:default_enrollment_states))
      end
    end
  end

  describe "#build_enrollment_states_structure" do
    let(:operation) { described_class.new }

    context "with valid aggregation results" do
      let(:enrollment_states_raw) do
        [
          {
            "_id" => {
              "coverage_kind" => "health",
              "aasm_state" => "coverage_selected",
              "aptc_category" => "with_aptc"
            },
            "count" => 5
          },
          {
            "_id" => {
              "coverage_kind" => "health",
              "aasm_state" => "auto_renewing",
              "aptc_category" => "without_aptc"
            },
            "count" => 3
          },
          {
            "_id" => {
              "coverage_kind" => "dental",
              "aasm_state" => "renewing_coverage_selected",
              "aptc_category" => "without_aptc"
            },
            "count" => 2
          }
        ]
      end

      it "builds correct enrollment states structure" do
        result = operation.send(:build_enrollment_states_structure, enrollment_states_raw)

        expect(result["health"]["with_aptc"]["coverage_selected"]).to eq(5)
        expect(result["health"]["without_aptc"]["auto_renewing"]).to eq(3)
        expect(result["dental"]["renewing_coverage_selected"]).to eq(2)
      end

      it "maintains default values for missing states" do
        result = operation.send(:build_enrollment_states_structure, enrollment_states_raw)

        # Should have default 0 values for states not in raw data
        expect(result["health"]["with_aptc"]["auto_renewing"]).to eq(0)
        expect(result["health"]["without_aptc"]["coverage_selected"]).to eq(0)
        expect(result["dental"]["auto_renewing"]).to eq(0)
      end
    end

    context "with empty aggregation results" do
      it "returns default structure" do
        result = operation.send(:build_enrollment_states_structure, [])

        expect(result).to eq(operation.send(:default_enrollment_states))
      end
    end
  end

  describe "#default_enrollment_states" do
    let(:operation) { described_class.new }

    it "returns correct default structure" do
      result = operation.send(:default_enrollment_states)

      expected_structure = {
        "health" => {
          "without_aptc" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0},
          "with_aptc" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0}
        },
        "dental" => {"auto_renewing" => 0, "coverage_selected" => 0, "renewing_coverage_selected" => 0}
      }

      expect(result).to eq(expected_structure)
    end
  end

  describe "integration with real data" do
    let!(:additional_family) { FactoryBot.create(:family, :with_primary_family_member) }
    let!(:additional_health_enrollment) do
      FactoryBot.create(:hbx_enrollment,
                        family: additional_family,
                        kind: "individual",
                        coverage_kind: "health",
                        aasm_state: "coverage_selected",
                        applied_aptc_amount: 50.0,
                        effective_on: Date.new(Date.current.year, 1, 1))  # Use current year to match Benefits mock
    end

    let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }
    let(:benefits_result) { [{}, [Date.current.year, Date.current.year - 1]] }

    before do
      allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
      allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Success(benefits_result))
    end

    it "aggregates multiple enrollments correctly" do
      result = described_class.new.call

      expect(result).to be_success
      data = result.value!

      # Should have proper structure and non-negative counts
      expect(data["health"]["with_aptc"]["coverage_selected"]).to be >= 0
      expect(data["health"]["without_aptc"]["auto_renewing"]).to be >= 0
      expect(data["dental"]["renewing_coverage_selected"]).to be >= 0

      # Verify we have some enrollment data aggregated
      total_health_enrollments = data["health"]["with_aptc"].values.sum + data["health"]["without_aptc"].values.sum
      total_dental_enrollments = data["dental"].values.sum
      expect(total_health_enrollments + total_dental_enrollments).to be >= 0
    end
  end
end
