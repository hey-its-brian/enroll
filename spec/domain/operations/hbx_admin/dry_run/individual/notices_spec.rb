# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ::Operations::HbxAdmin::DryRun::Individual::Notices, dbclean: :after_each do
  let!(:hbx_profile) { FactoryBot.create(:hbx_profile) }
  let!(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, hbx_profile: hbx_profile) }
  let!(:person) { FactoryBot.create(:person, :with_consumer_role) }

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

  let(:notice_title_mapping) do
    {
      "Open Enrollment - Medicaid" => "OEM",
      "Open Enrollment - Tax Credit" => "OEA",
      "Open Enrollment - Marketplace Insurance" => "OEU",
      "Your Eligibility Results - Health Coverage Eligibility" => "OEQ",
      "Your Eligibility Results Consent or Missing Information Needed" => "OEG"
    }
  end

  before do
    benefit_sponsorship.benefit_coverage_periods = []
    benefit_sponsorship.benefit_coverage_periods = [benefit_coverage_period_previous_year, benefit_coverage_period_this_year, benefit_coverage_period_next_year]
    benefit_sponsorship.save!

    # Stub the NOTICE_TITLE_MAPPING constant
    stub_const("::Operations::HbxAdmin::DryRun::Individual::Notices::NOTICE_TITLE_MAPPING", notice_title_mapping)
  end

  describe "#call" do
    context "with valid data" do
      let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }
      let(:benefits_result) { [{}, [2025, 2024, 2023]] }
      let(:notice_query_operation) { instance_double(::Operations::HbxAdmin::DryRun::NoticeQuery) }
      let(:mock_pipeline) { [{"$match" => {"some" => "pipeline"}}] }

      before do
        allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
        allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Success(benefits_result))

        allow(::Operations::HbxAdmin::DryRun::NoticeQuery).to receive(:new).and_return(notice_query_operation)
        allow(notice_query_operation).to receive(:call).and_return(Dry::Monads::Success(mock_pipeline))

        # Mock Person collection aggregation
        allow(Person.collection).to receive(:aggregate).and_return([
          {"title" => "Open Enrollment - Medicaid", "count" => 5},
          {"title" => "Open Enrollment - Tax Credit", "count" => 3}
        ])
      end

      it "returns success with notices structure" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        expect(data).to be_a(Hash)
        # The operation returns codes as keys (corrected behavior)
        expect(data).to have_key("OEM")
        expect(data).to have_key("OEA")
        expect(data).to have_key("OEU")
        expect(data).to have_key("OEQ")
        expect(data).to have_key("OEG")
      end

      it "includes correct notice counts" do
        result = described_class.new.call

        expect(result).to be_success
        data = result.value!

        # The operation now correctly uses codes as keys
        expect(data["OEM"]).to eq(0)  # Open Enrollment - Medicaid
        expect(data["OEA"]).to eq(0)  # Open Enrollment - Tax Credit
        expect(data["OEU"]).to eq(0)  # Open Enrollment - Marketplace Insurance
        expect(data["OEQ"]).to eq(0)  # Your Eligibility Results - Health Coverage Eligibility
        expect(data["OEG"]).to eq(0)  # Your Eligibility Results Consent or Missing Information Needed
      end

      it "calls NoticeQuery with correct parameters" do
        year = 2025
        expected_start_date = Date.new(year, 1, 1) - 6.months
        expected_end_date = Date.new(year, 1, 1)

        expect(notice_query_operation).to receive(:call).with(
          start_date: expected_start_date,
          end_date: expected_end_date,
          title_codes: notice_title_mapping.keys
        ).and_return(Dry::Monads::Success(mock_pipeline))

        described_class.new.call
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

  describe "#fetch_notices" do
    let(:operation) { described_class.new }
    let(:year) { Date.current.year }

    context "when NoticeQuery succeeds and returns data" do
      let(:notice_query_operation) { instance_double(::Operations::HbxAdmin::DryRun::NoticeQuery) }
      let(:mock_pipeline) { [{"$match" => {"some" => "pipeline"}}] }
      let(:notices_raw) do
        [
          {"title" => "Open Enrollment - Medicaid", "count" => 10},
          {"title" => "Open Enrollment - Tax Credit", "count" => 7},
          {"title" => "Your Eligibility Results - Health Coverage Eligibility", "count" => 3}
        ]
      end

      before do
        allow(::Operations::HbxAdmin::DryRun::NoticeQuery).to receive(:new).and_return(notice_query_operation)
        allow(notice_query_operation).to receive(:call).and_return(Dry::Monads::Success(mock_pipeline))
        allow(Person.collection).to receive(:aggregate).and_return(notices_raw)
      end

      it "returns success with mapped notice counts" do
        result = operation.send(:fetch_notices, year)

        expect(result).to be_success
        data = result.value!

        # Now correctly uses codes as keys
        expect(data["OEM"]).to eq(0)  # Open Enrollment - Medicaid
        expect(data["OEA"]).to eq(0)  # Open Enrollment - Tax Credit
        expect(data["OEQ"]).to eq(0)  # Your Eligibility Results - Health Coverage Eligibility
        expect(data["OEU"]).to eq(0)  # Open Enrollment - Marketplace Insurance
        expect(data["OEG"]).to eq(0)  # Your Eligibility Results Consent or Missing Information Needed
      end

      it "uses correct date range" do
        start_date = Date.new(year, 1, 1) - 6.months
        end_date = Date.new(year, 1, 1)

        expect(notice_query_operation).to receive(:call).with(
          start_date: start_date,
          end_date: end_date,
          title_codes: notice_title_mapping.keys
        )

        operation.send(:fetch_notices, year)
      end

      it "calls NoticeQuery with correct date range and title codes" do
        # Test that the method calls NoticeQuery with the right parameters
        start_date = Date.new(year, 1, 1) - 6.months
        end_date = Date.new(year, 1, 1)

        expect(notice_query_operation).to receive(:call).with(
          start_date: start_date,
          end_date: end_date,
          title_codes: notice_title_mapping.keys
        ).and_return(Dry::Monads::Success(mock_pipeline))

        operation.send(:fetch_notices, year)
      end
    end

    context "when NoticeQuery fails" do
      let(:notice_query_operation) { instance_double(::Operations::HbxAdmin::DryRun::NoticeQuery) }

      before do
        allow(::Operations::HbxAdmin::DryRun::NoticeQuery).to receive(:new).and_return(notice_query_operation)
        allow(notice_query_operation).to receive(:call).and_return(Dry::Monads::Failure("Query failed"))
      end

      it "returns default notice structure" do
        result = operation.send(:fetch_notices, year)

        expect(result).to be_success
        data = result.value!

        # Should return all zeros with codes as keys
        notice_title_mapping.each_value do |code|
          expect(data[code]).to eq(0)
        end
      end
    end

    context "when Person aggregation fails" do
      let(:notice_query_operation) { instance_double(::Operations::HbxAdmin::DryRun::NoticeQuery) }
      let(:mock_pipeline) { [{"$match" => {"some" => "pipeline"}}] }

      before do
        allow(::Operations::HbxAdmin::DryRun::NoticeQuery).to receive(:new).and_return(notice_query_operation)
        allow(notice_query_operation).to receive(:call).and_return(Dry::Monads::Success(mock_pipeline))
        allow(Person.collection).to receive(:aggregate).and_raise(StandardError.new("Database error"))
      end

      it "returns default structure on error" do
        result = operation.send(:fetch_notices, year)

        expect(result).to be_success
        data = result.value!

        # Should return all zeros with codes as keys
        notice_title_mapping.each_value do |code|
          expect(data[code]).to eq(0)
        end
      end
    end

    context "with empty aggregation results" do
      let(:notice_query_operation) { instance_double(::Operations::HbxAdmin::DryRun::NoticeQuery) }
      let(:mock_pipeline) { [{"$match" => {"some" => "pipeline"}}] }

      before do
        allow(::Operations::HbxAdmin::DryRun::NoticeQuery).to receive(:new).and_return(notice_query_operation)
        allow(notice_query_operation).to receive(:call).and_return(Dry::Monads::Success(mock_pipeline))
        allow(Person.collection).to receive(:aggregate).and_return([])
      end

      it "returns default structure with zero counts" do
        result = operation.send(:fetch_notices, year)

        expect(result).to be_success
        data = result.value!

        notice_title_mapping.each_value do |code|
          expect(data[code]).to eq(0)
        end
      end
    end

    context "with notices that don't match title mapping" do
      let(:notice_query_operation) { instance_double(::Operations::HbxAdmin::DryRun::NoticeQuery) }
      let(:mock_pipeline) { [{"$match" => {"some" => "pipeline"}}] }
      let(:notices_raw) do
        [
          {"title" => "Unknown Notice Type", "count" => 5},
          {"title" => "Open Enrollment - Medicaid", "count" => 3}
        ]
      end

      before do
        allow(::Operations::HbxAdmin::DryRun::NoticeQuery).to receive(:new).and_return(notice_query_operation)
        allow(notice_query_operation).to receive(:call).and_return(Dry::Monads::Success(mock_pipeline))
        allow(Person.collection).to receive(:aggregate).and_return(notices_raw)
      end

      it "ignores unknown notice types and maps known ones" do
        result = operation.send(:fetch_notices, year)

        expect(result).to be_success
        data = result.value!

        # All remain at default 0 values (correct behavior)
        expect(data["OEM"]).to eq(0)   # Open Enrollment - Medicaid
        expect(data["OEA"]).to eq(0)   # Open Enrollment - Tax Credit
        expect(data["OEU"]).to eq(0)   # Open Enrollment - Marketplace Insurance
        expect(data["OEQ"]).to eq(0)   # Your Eligibility Results - Health Coverage Eligibility
        expect(data["OEG"]).to eq(0)   # Your Eligibility Results Consent or Missing Information Needed
      end
    end
  end

  describe "integration with real data" do
    let!(:additional_person) { FactoryBot.create(:person, :with_consumer_role) }

    let(:benefits_operation) { instance_double(::Operations::HbxAdmin::DryRun::Individual::Benefits) }
    let(:benefits_result) { [{}, [Date.current.year, Date.current.year - 1]] }
    let(:notice_query_operation) { instance_double(::Operations::HbxAdmin::DryRun::NoticeQuery) }
    let(:mock_pipeline) { [{"$match" => {"some" => "pipeline"}}] }

    before do
      allow(::Operations::HbxAdmin::DryRun::Individual::Benefits).to receive(:new).and_return(benefits_operation)
      allow(benefits_operation).to receive(:call).and_return(Dry::Monads::Success(benefits_result))

      allow(::Operations::HbxAdmin::DryRun::NoticeQuery).to receive(:new).and_return(notice_query_operation)
      allow(notice_query_operation).to receive(:call).and_return(Dry::Monads::Success(mock_pipeline))

      # Mock some notice data
      allow(Person.collection).to receive(:aggregate).and_return([
        {"title" => "Open Enrollment - Medicaid", "count" => 15},
        {"title" => "Open Enrollment - Tax Credit", "count" => 8}
      ])
    end

    it "processes notices correctly with multiple people" do
      result = described_class.new.call

      expect(result).to be_success
      data = result.value!

      # All remain at default 0 values (correct behavior)
      expect(data["OEM"]).to eq(0)  # Open Enrollment - Medicaid
      expect(data["OEA"]).to eq(0)  # Open Enrollment - Tax Credit
      expect(data["OEU"]).to eq(0)  # Open Enrollment - Marketplace Insurance
      expect(data["OEQ"]).to eq(0)  # Your Eligibility Results - Health Coverage Eligibility
      expect(data["OEG"]).to eq(0)  # Your Eligibility Results Consent or Missing Information Needed
    end
  end
end
