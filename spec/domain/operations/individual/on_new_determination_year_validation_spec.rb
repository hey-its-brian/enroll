# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Individual::OnNewDetermination, type: :model, dbclean: :after_each do
  before :each do
    TimeKeeper.set_date_of_record_unprotected!(Date.new(2026, 1, 15)) # Set date to January 15, 2026
    DatabaseCleaner.clean
  end

  after :each do
    TimeKeeper.set_date_of_record_unprotected!(Date.today)
  end

  let(:site_key) { EnrollRegistry[:enroll_app].setting(:site_key).item.upcase }
  let!(:person) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member_and_dependent, person: person) }
  let(:effective_date) { Date.new(2025, 1, 1) }
  let(:current_effective_date) { Date.new(2026, 1, 1) }
  let!(:rating_area) { FactoryBot.create_default(:benefit_markets_locations_rating_area, active_year: 2026) }
  let!(:service_area) { FactoryBot.create_default(:benefit_markets_locations_service_area, active_year: 2026) }

  let!(:hbx_profile) { FactoryBot.create(:hbx_profile, :normal_ivl_open_enrollment) }

  # Add tax household setup for APTC calculations
  let!(:tax_household_2025) do
    FactoryBot.create(
      :tax_household,
      household: family.active_household,
      effective_starting_on: Date.new(2025, 1, 1),
      effective_ending_on: Date.new(2025, 12, 31)
    )
  end

  let!(:tax_household_2026) do
    FactoryBot.create(
      :tax_household,
      household: family.active_household,
      effective_starting_on: Date.new(2026, 1, 1),
      effective_ending_on: Date.new(2026, 12, 31)
    )
  end

  let!(:eligibility_determination_2025) do
    FactoryBot.create(
      :eligibility_determination,
      tax_household: tax_household_2025,
      determined_at: Date.new(2025, 1, 1)
    )
  end

  let!(:eligibility_determination_2026) do
    FactoryBot.create(
      :eligibility_determination,
      tax_household: tax_household_2026,
      determined_at: Date.new(2026, 1, 1)
    )
  end

  let!(:product_2025) do
    FactoryBot.create(
      :benefit_markets_products_health_products_health_product,
      :with_issuer_profile,
      benefit_market_kind: :aca_individual,
      kind: :health,
      service_area: service_area,
      csr_variant_id: '01',
      metal_level_kind: 'silver',
      application_period: Date.new(2025, 1, 1)..Date.new(2025, 12, 31)
    )
  end

  let!(:product_2026) do
    FactoryBot.create(
      :benefit_markets_products_health_products_health_product,
      :with_issuer_profile,
      benefit_market_kind: :aca_individual,
      kind: :health,
      service_area: service_area,
      csr_variant_id: '01',
      metal_level_kind: 'silver',
      application_period: Date.new(2026, 1, 1)..Date.new(2026, 12, 31)
    )
  end

  let!(:enrollment_2025) do
    enrollment = FactoryBot.create(
      :hbx_enrollment,
      :individual_unassisted,
      household: family.active_household,
      family: family,
      product: product_2025,
      effective_on: effective_date,
      aasm_state: "coverage_selected",
      applied_aptc_amount: 100.0,
      consumer_role: person.consumer_role
    )

    FactoryBot.create(
      :hbx_enrollment_member,
      hbx_enrollment: enrollment,
      applicant_id: family.primary_applicant.id,
      is_subscriber: true,
      eligibility_date: effective_date
    )

    enrollment.reload
    enrollment
  end

  let!(:enrollment_2026) do
    enrollment = FactoryBot.create(
      :hbx_enrollment,
      :individual_unassisted,
      household: family.active_household,
      family: family,
      product: product_2026,
      effective_on: current_effective_date,
      aasm_state: "coverage_selected",
      applied_aptc_amount: 100.0,
      consumer_role: person.consumer_role
    )

    FactoryBot.create(
      :hbx_enrollment_member,
      hbx_enrollment: enrollment,
      applicant_id: family.primary_applicant.id,
      is_subscriber: true,
      eligibility_date: current_effective_date
    )

    enrollment.reload
    enrollment
  end

  describe 'year validation for OnNewDetermination' do
    context 'when trying to auto-generate enrollments for 2025 in 2026' do
      it 'should prevent auto-generation for past year' do
        result = subject.call({ family: family, year: 2025 })
        expect(result).to be_success
        expect(result.success).to eq(:no_eligible_enrollments)
        expect(family.hbx_enrollments.count).to eq(2) # No new enrollments created
      end
    end

    context 'when trying to auto-generate enrollments for 2026 in 2026' do
      it 'should allow auto-generation for current year' do
        result = subject.call({ family: family, year: 2026 })
        expect(result).to be_success
      end
    end

    context 'when trying to auto-generate enrollments for 2027 in 2026' do
      it 'should allow auto-generation for future year' do
        result = subject.call({ family: family, year: 2027 })
        expect(result).to be_success
      end
    end
  end

  describe 'logging behavior' do
    it 'should log when preventing past year auto-generation' do
      expect(Rails.logger).to receive(:info).with(/Enrollment auto-generation prevented for past year 2025 when current year is 2026/)
      subject.call({ family: family, year: 2025 })
    end
  end

  describe 'APTC update mechanism year validation' do
    context 'when past year enrollments somehow reach generate_enrollments' do
      let(:operation) { described_class.new }

      it 'should prevent APTC updates for past year enrollments' do
        allow(operation).to receive(:fetch_enrollments_to_renew).and_return(Dry::Monads::Success([enrollment_2025]))

        expect(Rails.logger).to receive(:info).with(/APTC update prevented for past year enrollment/)
        expect(::Insured::Forms::SelfTermOrCancelForm).not_to receive(:for_aptc_update_post)

        result = operation.call({ family: family, year: 2025 })
        expect(result).to be_success
        expect(result.success).to eq(:no_eligible_enrollments)
      end
    end

    context 'when current year enrollments reach generate_enrollments' do
      let(:operation) { described_class.new }

      it 'should allow APTC updates for current year enrollments' do
        allow(operation).to receive(:fetch_enrollments_to_renew).and_return(Dry::Monads::Success([enrollment_2026]))

        expect(Rails.logger).not_to receive(:info).with(/APTC update prevented for past year enrollment/)
        expect(::Insured::Forms::SelfTermOrCancelForm).to receive(:for_aptc_update_post)

        result = operation.call({ family: family, year: 2026 })
        expect(result).to be_success
        expect(result.success).to eq(:applied_aptc_to_enrollments)
      end
    end
  end
end