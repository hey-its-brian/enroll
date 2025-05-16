# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Entities::BenchmarkProducts::BenchmarkProduct, dbclean: :after_each do
  describe '.new' do
    let(:valid_parmas_with_application) do
      {
        data_source: 'fa_application',
        application_id: BSON::ObjectId.new,
        effective_date: TimeKeeper.date_of_record,
        primary_rating_address_id: BSON::ObjectId.new,
        rating_area_id: BSON::ObjectId.new,
        exchange_provided_code: 'R-ME001',
        service_area_ids: [BSON::ObjectId.new],
        household_group_benchmark_ehb_premium: 200.90,
        households: [
          {
            household_id: 'a12bs6dbs1',
            type_of_household: 'adult_only',
            household_benchmark_ehb_premium: 200.90,
            health_product_hios_id: '123',
            health_product_id: BSON::ObjectId.new,
            health_ehb: 0.99,
            household_health_benchmark_ehb_premium: 200.90,
            health_product_covers_pediatric_dental_costs: true,
            members: [
              {
                applicant_id: BSON::ObjectId.new,
                coverage_start_on: TimeKeeper.date_of_record,
                relationship_with_primary: 'self'
              }
            ]
          }
        ]
      }
    end

    let(:valid_parmas_with_family) do
      {
        data_source: 'family',
        family_id: BSON::ObjectId.new,
        effective_date: TimeKeeper.date_of_record,
        primary_rating_address_id: BSON::ObjectId.new,
        rating_area_id: BSON::ObjectId.new,
        exchange_provided_code: 'R-ME001',
        service_area_ids: [BSON::ObjectId.new],
        household_group_benchmark_ehb_premium: 200.90,
        origin: 'enrollment_purchase',
        households: [
          {
            household_id: 'a12bs6dbs1',
            type_of_household: 'adult_only',
            household_benchmark_ehb_premium: 200.90,
            health_product_hios_id: '123',
            health_product_id: BSON::ObjectId.new,
            health_ehb: 0.99,
            household_health_benchmark_ehb_premium: 200.90,
            health_product_covers_pediatric_dental_costs: true,
            members: [
              {
                family_member_id: BSON::ObjectId.new,
                relationship_with_primary: 'self',
                date_of_birth: TimeKeeper.date_of_record - 30.years,
                age_on_effective_date: 30
              }
            ]
          }
        ]
      }
    end

    let(:valid_parmas_without_family) do
      {
        data_source: 'anonymous',
        rating_address: {
          county: 'County Name',
          zip: '11111',
          state: 'ME'
        },
        effective_date: TimeKeeper.date_of_record,
        rating_area_id: BSON::ObjectId.new,
        exchange_provided_code: 'R-ME001',
        service_area_ids: [BSON::ObjectId.new],
        household_group_benchmark_ehb_premium: 200.90,
        households: [
          {
            household_id: 'a12bs6dbs1',
            type_of_household: 'adult_only',
            household_benchmark_ehb_premium: 200.90,
            health_product_hios_id: '123',
            health_product_id: BSON::ObjectId.new,
            health_ehb: 0.99,
            household_health_benchmark_ehb_premium: 200.90,
            health_product_covers_pediatric_dental_costs: true,
            members: [
              {
                relationship_with_primary: 'self',
                date_of_birth: TimeKeeper.date_of_record - 30.years,
                age_on_effective_date: 30
              }
            ]
          }
        ]
      }
    end

    context 'with application' do
      before do
        validated_params = Validators::BenchmarkProducts::BenchmarkProductContract.new.call(valid_parmas_with_application).to_h
        @result = described_class.new(validated_params)
      end

      it 'returns the benchmark product entity with expected params' do
        expect(@result).to be_a(described_class)
        expect(@result.to_h.keys.sort).to eq(valid_parmas_with_application.keys.sort)
        expect(@result.application_id).to be_a(BSON::ObjectId)
        expect(@result.households.first.members.first.applicant_id).to be_a(BSON::ObjectId)
        expect(@result.data_source).to eq('fa_application')
      end
    end

    context 'with family' do
      before do
        validated_params = Validators::BenchmarkProducts::BenchmarkProductContract.new.call(valid_parmas_with_family).to_h
        @result = described_class.new(validated_params)
      end

      it 'returns benchmark product entity object' do
        expect(@result).to be_a(described_class)
        expect(@result.to_h.keys.sort).to eq(valid_parmas_with_family.keys.sort)
        expect(@result.data_source).to eq('family')
      end
    end

    context 'without family' do
      before do
        validated_params = Validators::BenchmarkProducts::BenchmarkProductContract.new.call(valid_parmas_without_family).to_h
        @result = described_class.new(validated_params)
      end

      it 'returns benchmark product entity object' do
        expect(@result).to be_a(described_class)
        expect(@result.to_h.keys.sort).to eq(valid_parmas_without_family.keys.sort)
        expect(@result.data_source).to eq('anonymous')
      end
    end
  end
end
