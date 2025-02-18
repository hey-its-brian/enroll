# frozen_string_literal: true

require 'rails_helper'

class FakesController < ApplicationController
  include Aptc
end

describe FakesController do
  let(:person) { FactoryBot.build(:person, :with_consumer_role, dob: Date.new(system_year - 25, 1, 19))}
  let!(:system_year) { Date.today.year }
  let!(:start_of_year) { Date.new(system_year) }
  let!(:family) { FactoryBot.create(:family, :with_primary_family_member, person: person) }
  let!(:hbx_enrollment) do
    FactoryBot.create(:hbx_enrollment,
                      :with_silver_health_product,
                      :individual_unassisted,
                      effective_on: start_of_year,
                      family: family,
                      household: family.active_household,
                      coverage_kind: "health",
                      rating_area_id: BSON::ObjectId.new)
  end
  let!(:hbx_enrollment_member) do
    FactoryBot.create(:hbx_enrollment_member, is_subscriber: true,
                                              hbx_enrollment: hbx_enrollment, applicant_id: family.primary_applicant.id,
                                              coverage_start_on: start_of_year, eligibility_date: start_of_year)
  end
  let(:max_aptc)   { 637.0 }
  let(:tax_household) { double("TaxHousehold ")}

  context "#get_shopping_tax_household_from_person" do
    it "should get nil without person" do
      expect(subject.get_shopping_tax_household_from_person(nil, 2015)).to eq nil
    end

    it "should get nil when person without consumer_role" do
      allow(person).to receive(:has_active_consumer_role?).and_return true
      expect(subject.get_shopping_tax_household_from_person(person, 2015)).to eq nil
    end
  end

  context 'MTHH enabled' do
    before do
      EnrollRegistry[:temporary_configuration_enable_multi_tax_household_feature].feature.stub(:is_enabled).and_return(true)
      EnrollRegistry[:enroll_app].settings(:default_aptc_percentage).stub(:item).and_return(100)
      allow(::Operations::PremiumCredits::FindAptc).to receive(:new).and_return(
        double(
          call: double(
            success?: true,
            value!: max_aptc
          )
        )
      )
    end

    context "#fetch_max_aptc" do
      it "should fetch max_aptc" do
        expect(subject.fetch_max_aptc(hbx_enrollment)).to eq max_aptc
      end
    end

    context "#fetch_elected_aptc" do
      it "should fetch_elected_aptc" do
        default_aptc_percentage = EnrollRegistry[:enroll_app].setting(:default_aptc_percentage).item
        eligible_aptc = (max_aptc * default_aptc_percentage) / 100
        expect(subject.fetch_elected_aptc(max_aptc)).to eq eligible_aptc
      end
    end
  end

  context 'MTHH not enabled' do
    before do
      EnrollRegistry[:temporary_configuration_enable_multi_tax_household_feature].feature.stub(:is_enabled).and_return(false)
      EnrollRegistry[:enroll_app].settings(:default_aptc_percentage).stub(:item).and_return(100)
      allow(tax_household).to receive(:total_aptc_available_amount_for_enrollment).and_return(max_aptc)
    end

    context "#fetch_max_aptc" do
      it "should fetch max_aptc" do
        expect(subject.fetch_max_aptc(hbx_enrollment, tax_household)).to eq max_aptc
      end
    end

    context "#fetch_elected_aptc" do
      it "should fetch_elected_aptc" do
        default_aptc_percentage = EnrollRegistry[:enroll_app].setting(:default_aptc_percentage).item
        eligible_aptc = (max_aptc * default_aptc_percentage) / 100
        expect(subject.fetch_elected_aptc(max_aptc)).to eq eligible_aptc
      end
    end
  end
end
