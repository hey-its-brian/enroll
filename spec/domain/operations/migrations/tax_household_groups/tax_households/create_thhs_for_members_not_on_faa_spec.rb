# frozen_string_literal: true

require 'rails_helper'
require File.join(Rails.root, 'spec/shared_contexts/benchmark_products')

RSpec.describe Operations::Migrations::TaxHouseholdGroups::TaxHouseholds::CreateThhsForMembersNotOnFaa do
  include Dry::Monads[:do, :result]

  subject { described_class.new }

  let(:person1) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family1) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }
  let!(:dependent_family_member) do
    FactoryBot.create(:family_member, family: family1, person: person2)
  end

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

  let(:primary_hbx_enrollment_member) do
    FactoryBot.build(:hbx_enrollment_member, is_subscriber: true,
                                             applicant_id: family1.family_members.first.id,
                                             coverage_start_on: TimeKeeper.date_of_record,
                                             eligibility_date: TimeKeeper.date_of_record)
  end

  let(:dependent_hbx_enrollment_member) do
    FactoryBot.build(:hbx_enrollment_member, is_subscriber: false,
                                             applicant_id: dependent_family_member.id,
                                             coverage_start_on: TimeKeeper.date_of_record,
                                             eligibility_date: TimeKeeper.date_of_record)
  end

  let(:hbx_enrollment1) do
    FactoryBot.create(:hbx_enrollment,
                      :with_health_product,
                      consumer_role: person1.consumer_role,
                      effective_on: TimeKeeper.date_of_record.beginning_of_year,
                      household: family1.active_household, kind: "individual", family: family1,
                      hbx_enrollment_members: [primary_hbx_enrollment_member, dependent_hbx_enrollment_member],
                      applied_aptc_amount: Money.new(50_00))
  end

  let!(:tax_household1) do
    tax_household_group1.tax_households.first
  end

  let!(:tax_household_member1) {FactoryBot.create(:tax_household_member, applicant_id: family1.family_members.first.id, tax_household: tax_household1)}


  let!(:thhm_enrollment_members) do
    [hbx_enrollment1.hbx_enrollment_members[0]].collect do |member|
      FactoryBot.build(:tax_household_member_enrollment_member, hbx_enrollment_member_id: member.id, family_member_id: member.applicant_id, tax_household_member_id: "123")
    end
  end

  let!(:thhe) do
    tax_household_enrollment = FactoryBot.build(:tax_household_enrollment, enrollment_id: hbx_enrollment1.id, tax_household_id: tax_household1.id,
                                                                           health_product_hios_id: hbx_enrollment1.product.hios_id,
                                                                           household_health_benchmark_ehb_premium: Money.new(100_000),
                                                                           household_dental_benchmark_ehb_premium: Money.new(50_000),
                                                                           dental_product_hios_id: nil, tax_household_members_enrollment_members: thhm_enrollment_members)
    tax_household_enrollment.save
    tax_household_enrollment
  end

  let(:csv_file_name) { "#{Rails.root}/create_thh_members_not_on_faa_report.csv" }

  after :all do
    csv_path = "#{Rails.root}/create_thh_members_not_on_faa_report.csv"
    File.delete(csv_path) if File.exist?(csv_path)
  end

  context 'when enrollment member does not exist in a tax household' do
    before do
      hbx_enrollment1
    end

    it 'returns a success result' do
      expect(family1.tax_household_groups.last.tax_households.count).to eq 1
      expect(TaxHouseholdEnrollment.all.count).to eq 1
      result = subject.call({year: TimeKeeper.date_of_record.year})
      family1.reload
      expect(family1.tax_household_groups.last.tax_households.count).to eq 2
      expect(TaxHouseholdEnrollment.all.count).to eq 2
      expect(result.success).to eq(
        "Successfully processed all enrollments. Please check the report: #{csv_file_name} for more details."
      )
    end
  end
end
