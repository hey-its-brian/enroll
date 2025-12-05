# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Products::FetchCrossWalkProducts do
  let(:operation) { described_class.new }

  let!(:base_product)     { FactoryBot.create(:benefit_markets_products_health_products_health_product, hios_base_id: '33653ME0560001') }
  let!(:renewal_product) do
    FactoryBot.create(:benefit_markets_products_health_products_health_product, metal_level_kind: :silver, benefit_market_kind: :aca_individual,
                                                                                application_period: (TimeKeeper.date_of_record.next_year.beginning_of_year..TimeKeeper.date_of_record.next_year.end_of_year), hios_id: base_product.hios_id)
  end
  let(:person) { FactoryBot.create(:person, :with_family) }
  let(:family) { person.primary_family }
  let(:rating_area) { FactoryBot.create(:benefit_markets_locations_rating_area) }

  let(:base_enrollment) { FactoryBot.create(:hbx_enrollment, family: family, household: family.active_household, kind: 'individual', effective_on: TimeKeeper.date_of_record.beginning_of_month.to_date, product_id: base_product.id) }
  let(:renewal_enrollment) { FactoryBot.create(:hbx_enrollment, family: family, household: family.active_household, kind: 'individual', effective_on: TimeKeeper.date_of_record.next_year.beginning_of_year.to_date) }

  before do
    base_product.renewal_product = renewal_product
    base_product.save
  end

  describe '#validate' do
    it 'fails when base_enrollment is missing' do
      result = subject.call({ base_enrollment: nil, renewal_year: renewal_enrollment.effective_on.year })
      expect(result).to be_failure
      expect(result.failure).to eq('Missing Base Enrollment')
    end

    it 'fails when renewal_year is missing' do
      result = subject.call({ base_enrollment: base_enrollment, renewal_year: nil })
      expect(result).to be_failure
      expect(result.failure).to eq('Missing Renewal Year')
    end

    it 'fails when renewal_product is missing' do
      result = subject.call({ base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: nil })
      expect(result).to be_failure
      expect(result.failure).to eq('Missing Default Renewal Product')
    end

    it 'succeeds when all required params are present' do
      result = subject.call({ base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: base_product.renewal_product })
      expect(result).to be_success
    end
  end

  describe '#call' do
    context 'renewal year not in 2025/2026' do
      before { allow(renewal_enrollment).to receive(:effective_on).and_return(Date.new(2024, 1, 1)) }

      it 'returns the default renewal product' do
        result = operation.call(base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: base_product.renewal_product)
        expect(result).to be_success
        expect(result.value!).to eq(renewal_product)
      end
    end

    context 'renewal year is 2025 with county in allowlist and known mapping' do
      before do
        allow(renewal_enrollment).to receive(:effective_on).and_return(Date.new(2025, 1, 1))
        allow(base_enrollment).to receive(:consumer_role).and_return(double('consumer_role', rating_address: double('rating_address', county: 'Hancock')))
        mapped_hios_base = '33653ME0560006'
        @csr_01_product = FactoryBot.create(
          :benefit_markets_products_health_products_health_product,
          hios_id: "#{mapped_hios_base}-01"
        )

        scope = double('HealthProduct.by_year scope')
        allow(::BenefitMarkets::Products::HealthProducts::HealthProduct).to receive(:by_year)
          .with(2025).and_return(scope)
        allow(scope).to receive(:where)
          .with({ hios_id: "#{mapped_hios_base}-01" })
          .and_return(double(first: @csr_01_product))
      end

      it 'returns the CSR 01 crosswalk product' do
        result = operation.call(base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: base_product.renewal_product)
        expect(result).to be_success
        expect(result.value!).to eq(@csr_01_product)
      end
    end

    context 'renewal year is 2026 with county in allowlist and known mapping' do
      before do
        allow(renewal_enrollment).to receive(:effective_on).and_return(Date.new(2026, 1, 1))
        allow(base_enrollment).to receive(:consumer_role).and_return(double('consumer_role', rating_address: double('rating_address', county: 'Hancock')))
        base_product.update_attributes!(hios_base_id: '33653ME0530010')
        mapped_hios_base = '33653ME0560006'
        @csr_01_product = FactoryBot.create(
          :benefit_markets_products_health_products_health_product,
          hios_id: "#{mapped_hios_base}-01"
        )

        scope = double('HealthProduct.by_year scope')
        allow(::BenefitMarkets::Products::HealthProducts::HealthProduct).to receive(:by_year)
          .with(2026).and_return(scope)
        allow(scope).to receive(:where)
          .with({ hios_id: "#{mapped_hios_base}-01" })
          .and_return(double(first: @csr_01_product))
      end

      it 'returns the CSR 01 crosswalk product' do
        result = operation.call(base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: base_product.renewal_product)
        expect(result).to be_success
        expect(result.value!).to eq(@csr_01_product)
      end
    end

    context 'renewal year is 2025 but county not in allowlist' do
      before do
        allow(renewal_enrollment).to receive(:effective_on).and_return(Date.new(2025, 1, 1))
        allow(base_enrollment).to receive(:consumer_role).and_return(double('consumer_role', rating_address: double('rating_address', county: 'Test_County')))
      end

      it 'falls back to default renewal product' do
        result = operation.call(base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: base_product.renewal_product)
        expect(result).to be_success
        expect(result.value!).to eq(renewal_product)
      end
    end

    context 'renewal year 2025 with allowed county but no mapping for current hios_base_id' do
      before do
        allow(renewal_enrollment).to receive(:effective_on).and_return(Date.new(2025, 1, 1))
        consumer_role = double('consumer_role', rating_address: double('rating_address', county: 'Test_County'))
        allow(base_enrollment).to receive(:consumer_role).and_return(consumer_role)
        allow(base_product).to receive(:hios_base_id).and_return('UNKNOWN_BASE')
      end

      it 'returns default renewal product' do
        result = operation.call(base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: base_product.renewal_product)
        expect(result).to be_success
        expect(result.value!).to eq(renewal_product)
      end
    end

    context 'renewal year 2025 with mapping present but CSR 01 product not found' do
      before do
        allow(renewal_enrollment).to receive(:effective_on).and_return(Date.new(2025, 1, 1))
        allow(base_enrollment).to receive(:consumer_role).and_return(double('consumer_role', rating_address: double('rating_address', county: 'Hancock')))
        base_product.update_attributes!(hios_base_id: '33653ME0560001')

        scope = double('HealthProduct.by_year scope')
        allow(::BenefitMarkets::Products::HealthProducts::HealthProduct).to receive(:by_year)
          .with(2025).and_return(scope)
        allow(scope).to receive(:where)
          .with({ hios_id: "33653ME0560006-01" })
          .and_return(double(first: nil))
      end

      it 'returns Success with nil, matching implementation' do
        result = operation.call(base_enrollment: base_enrollment, renewal_year: renewal_enrollment.effective_on.year, renewal_product: base_product.renewal_product)
        expect(result).to be_success
        expect(result.value!).to be_nil
      end
    end
  end
end