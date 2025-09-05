# frozen_string_literal: true

require 'rails_helper'

# corresponds to service object called from `rails runner script/oeg_oeq_notice_triggers.rb oeg_oeq`
RSpec.describe Operations::HbxEnrollments::DetermineOeNoticeRecipients, dbclean: :around_each do
  let(:logger_double) { instance_double(Logger, info: true) }

  let!(:hbx_profile) { FactoryBot.create(:hbx_profile) }
  let!(:benefit_sponsorship) { FactoryBot.create(:benefit_sponsorship, :open_enrollment_coverage_period, hbx_profile: hbx_profile) }
  let(:product) { FactoryBot.create(:benefit_markets_products_health_products_health_product, metal_level_kind: :silver, benefit_market_kind: :aca_individual) }

  let(:hbx_enrollment_member1) do
    FactoryBot.build(:hbx_enrollment_member,
                     is_subscriber: true,
                     applicant_id: family1.family_members[0].id,
                     coverage_start_on: TimeKeeper.date_of_record.beginning_of_month,
                     eligibility_date: TimeKeeper.date_of_record.beginning_of_month)
  end

  let!(:enrollment1) do
    FactoryBot.create(:hbx_enrollment,
                      :with_enrollment_members,
                      product: product,
                      family: family1,
                      household: family1.active_household,
                      hbx_enrollment_members: [hbx_enrollment_member1],
                      aasm_state: "coverage_selected",
                      kind: "individual",
                      effective_on: TimeKeeper.date_of_record,
                      rating_area_id: person1.consumer_role.rating_address.id,
                      consumer_role_id: person1.consumer_role.id)
  end

  let(:hbx_enrollment_member2) do
    FactoryBot.build(:hbx_enrollment_member,
                     is_subscriber: true,
                     applicant_id: family2.family_members[0].id,
                     coverage_start_on: TimeKeeper.date_of_record.beginning_of_month,
                     eligibility_date: TimeKeeper.date_of_record.beginning_of_month)
  end

  let!(:enrollment2) do
    FactoryBot.create(:hbx_enrollment,
                      :with_enrollment_members,
                      product: product,
                      family: family2,
                      household: family2.active_household,
                      hbx_enrollment_members: [hbx_enrollment_member2],
                      aasm_state: "coverage_selected",
                      kind: "individual",
                      effective_on: TimeKeeper.date_of_record,
                      rating_area_id: person2.consumer_role.rating_address.id,
                      consumer_role_id: person2.consumer_role.id)
  end

  let(:person1) { FactoryBot.create(:person, :with_consumer_role, :with_ssn) }
  let(:family1) { FactoryBot.create(:family, :with_primary_family_member, person: person1) }

  let(:person2) { FactoryBot.create(:person, :with_consumer_role, :with_ssn) }
  let(:family2) { FactoryBot.create(:family, :with_primary_family_member, person: person2) }

  let(:faa1) do
    FactoryBot.create(
      :financial_assistance_application,
      :draft,
      family_id: family1.id,
      assistance_year: TimeKeeper.date_of_record.next_year.year,
      applicants: [
        FactoryBot.create(
          :financial_assistance_applicant,
          family_member_id: family1.primary_family_member.id,
          first_name: person2.first_name,
          last_name: person2.last_name,
          gender: person2.gender,
          dob: person2.dob,
          person_hbx_id: person2.hbx_id,
          is_applying_coverage: true,
          is_primary_applicant: true
        )
      ]
    )
  end

  let(:faa2) do
    FactoryBot.create(
      :financial_assistance_application,
      family_id: family2.id,
      assistance_year: TimeKeeper.date_of_record.year,
      applicants: [
        FactoryBot.create(
          :financial_assistance_applicant,
          family_member_id: family2.primary_family_member.id,
          first_name: person2.first_name,
          last_name: person2.last_name,
          gender: person2.gender,
          dob: person2.dob,
          person_hbx_id: person2.hbx_id,
          is_applying_coverage: true,
          is_primary_applicant: true
        )
      ]
    )
  end

  before do
    allow(Logger).to receive(:new).and_return(logger_double)
    allow(logger_double).to receive(:info)
    enrollment1
    enrollment2
    faa1
    faa2
  end

  it "returns failure for invalid enrollment_type" do
    result = described_class.new.call(notice_type: "invalid_type")
    expect(result).to be_failure
    expect(result.failure).to match(/Not a valid NoticeType/)
  end

  it "processes OEG families when 'oeg' is passed" do
    expect(logger_double).to receive(:info).with(/Triggered OE event for family_id: #{family1.id}, index: 0/)
    result = described_class.new.call(notice_type: "oeg")
    expect(result).to be_success
  end

  it "processes OEQ families when 'oeq' is passed" do
    expect(logger_double).to receive(:info).with(/Triggered OE event for family_id: #{family2.id}, index: 0/)
    result = described_class.new.call(notice_type: "oeq")
    expect(result).to be_success
  end

  context 'for oeg_oeq' do
    it "processes both OEG and OEQ families when 'oeg_oeq' is passed" do
      expect(logger_double).to receive(:info).with(/Triggered OE event for family_id: #{family1.id}, index: 0/)
      expect(logger_double).to receive(:info).with(/Triggered OE event for family_id: #{family2.id}, index: 1/)
      result = described_class.new.call(notice_type: "oeg_oeq")
      expect(result).to be_success
    end
  end
end
