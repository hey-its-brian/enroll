# frozen_string_literal: true

require 'rails_helper'
require File.join(Rails.root, 'spec/shared_contexts/benchmark_products')

RSpec.describe Operations::Migrations::TaxHouseholdEnrollments::Create do
  include Dry::Monads[:do, :result]

  subject { described_class.new }

  let(:person1) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family1) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }
  let!(:tax_household_group1) do
    family1.tax_household_groups.create!(
      assistance_year: TimeKeeper.date_of_record.year,
      source: 'Faa',
      start_on: TimeKeeper.date_of_record.beginning_of_year,
      tax_households: [
        FactoryBot.build(:tax_household, household: family1.active_household)
      ]
    )
  end
  let(:hbx_enrollment_member) do
    FactoryBot.build(:hbx_enrollment_member, is_subscriber: true,
                                             applicant_id: family1.family_members.first.id,
                                             coverage_start_on: TimeKeeper.date_of_record,
                                             eligibility_date: TimeKeeper.date_of_record)
  end
  let(:hbx_enrollment1) do
    FactoryBot.create(:hbx_enrollment,
                      :with_health_product,
                      consumer_role: person1.consumer_role,
                      effective_on: TimeKeeper.date_of_record.beginning_of_year,
                      household: family1.active_household, kind: "individual", family: family1,
                      hbx_enrollment_members: [hbx_enrollment_member],
                      applied_aptc_amount: Money.new(50_00))
  end

  let!(:tax_household1) do
    tax_household_group1.tax_households.first
  end

  let!(:tax_household_member1) {FactoryBot.create(:tax_household_member, applicant_id: family1.family_members.first.id, tax_household: tax_household1)}

  let(:benchmark_product_hash) do
    {
      family_id: family1.id,
      effective_date: hbx_enrollment1.effective_on,
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
          health_product_id: hbx_enrollment1.id,
          health_ehb: 1.0,
          household_health_benchmark_ehb_premium: 200.90,
          health_product_covers_pediatric_dental_costs: false,
          members: [
            {
              family_member_id: family1.primary_applicant.id,
              relationship_with_primary: 'self',
              date_of_birth: person1.dob,
              age_on_effective_date: 30
            }
          ]
        }
      ]
    }
  end
  let(:benchmark_product) { ::Operations::BenchmarkProducts::Initialize.new.call(benchmark_product_hash).success }

  let(:csv_file_name) { "#{Rails.root}/reinstated_enrollments_with_thh_enrs_creation_report.csv" }

  after :all do
    csv_path = "#{Rails.root}/reinstated_enrollments_with_thh_enrs_creation_report.csv"
    File.delete(csv_path) if File.exist?(csv_path)
  end

  context 'when reinstated enrollment with no tax household exists' do
    before do
      hbx_enrollment1
      allow(::Operations::BenchmarkProducts::IdentifySlcspWithPediatricDentalCosts).to receive(:new).and_return(
        double('IdentifySlcspWithPediatricDentalCosts', call: Success(benchmark_product))
      )
    end

    it 'returns a success result' do
      expect(hbx_enrollment1.tax_household_enrollments.count).to eq 0
      expect(subject.call(enrollment_hbx_ids: [hbx_enrollment1.hbx_id]).success).to include("Created Tax household enrollments successfully")
      expect(hbx_enrollment1.reload.tax_household_enrollments.count).to eq 1
    end
  end
end
