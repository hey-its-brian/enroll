# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Operations::Migrations::TaxHouseholdEnrollments::CreateForReinstatedEnrollments do
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
  let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role) }
  let(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }

  let!(:tax_household_group2) do
    family2.tax_household_groups.create!(
      assistance_year: TimeKeeper.date_of_record.year,
      source: 'Faa',
      start_on: TimeKeeper.date_of_record.beginning_of_year,
      tax_households: [
        FactoryBot.build(:tax_household, household: family2.active_household)
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
                      effective_on: TimeKeeper.date_of_record.beginning_of_year,
                      household: family1.active_household, kind: "individual", family: family1,
                      hbx_enrollment_members: [hbx_enrollment_member],
                      applied_aptc_amount: Money.new(50_00))
  end

  let(:reinstated_hbx_enrollment1) do
    FactoryBot.create(:hbx_enrollment,
                      :with_health_product,
                      household: family1.active_household, kind: "individual", family: family1,
                      effective_on: TimeKeeper.date_of_record.beginning_of_year + 1.month,
                      hbx_enrollment_members: [hbx_enrollment_member],
                      predecessor_enrollment_id: hbx_enrollment1.id,
                      applied_aptc_amount: Money.new(50_00),
                      workflow_state_transitions: [FactoryBot.build(:workflow_state_transition, to_state: "coverage_reinstated")])
  end

  let!(:tax_household1) do
    tax_household_group1.tax_households.first
  end

  let!(:tax_household2) do
    tax_household_group2.tax_households.first
  end

  let!(:thhm_enrollment_members) do
    hbx_enrollment1.hbx_enrollment_members.collect do |member|
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

  let(:csv_file_name) { "#{Rails.root}/reinstated_enrollments_with_thh_enrs_creation_report.csv" }

  after :all do
    csv_path = "#{Rails.root}/reinstated_enrollments_with_thh_enrs_creation_report.csv"
    File.delete(csv_path) if File.exist?(csv_path)
  end

  context 'when reinstated enrollment with no tax household exists' do
    before do
      reinstated_hbx_enrollment1
    end

    it 'returns a success result' do
      expect(reinstated_hbx_enrollment1.tax_household_enrollments.count).to eq 0
      result = subject.call(year: TimeKeeper.date_of_record.year).success
      expect(reinstated_hbx_enrollment1.reload.tax_household_enrollments.count).to eq 1
      expect(result).to eq(
        "Successfully created missing tax household enrollments for APTC enrollments. Please check the report: #{csv_file_name} for more details."
      )
    end

  end
end
