# frozen_string_literal: true

require 'rails_helper'
require File.join(Rails.root, 'spec/shared_contexts/benchmark_products')

RSpec.describe Operations::BenchmarkProducts::IdentifyRatingAndServiceAreas do
  describe '#call' do
    before do
      allow(EnrollRegistry[:enroll_app].settings(:rating_areas)).to receive(:item).and_return('county')
      allow(EnrollRegistry[:service_area].settings(:service_area_model)).to receive(:item).and_return('county')
      benchmark_product_model = ::Operations::BenchmarkProducts::Initialize.new.call(input_params).success
      _family, @benchmark_product_model = ::Operations::BenchmarkProducts::IdentifyTypeOfHousehold.new.call(benchmark_product_model).success
    end

    context 'when data_source is family' do
      include_context 'family with 2 family members with county_zip, rating_area & service_area'

      let(:input_params) do
        {
          data_source: 'family',
          family_id: family.id,
          effective_date: start_of_year,
          households: [
            {
              household_id: 'a12bs6dbs1',
              members: [
                {
                  family_member_id: family_member1.id,
                  relationship_with_primary: 'self'
                },
                {
                  family_member_id: family_member2.id,
                  relationship_with_primary: 'spouse'
                }
              ]
            }
          ]
        }
      end

      context 'valid input' do
        before { @result = subject.call({ family: family, benchmark_product_model: @benchmark_product_model }) }

        it 'return success' do
          expect(@result.success).to be_a(::Entities::BenchmarkProducts::BenchmarkProduct)
          expect(@result.success.rating_area_id).to eq(rating_area.id)
          expect(@result.success.exchange_provided_code).to eq(rating_area.exchange_provided_code)
          expect(@result.success.service_area_ids).to eq([service_area.id])
        end
      end

      context 'without rating address' do
        before do
          person1.addresses.destroy_all
          @result = subject.call({ family: family, benchmark_product_model: @benchmark_product_model })
        end

        it 'return failure with message' do
          expect(@result.failure).to eq("Unable to find Rating Address for PrimaryPerson with hbx_id: #{family.primary_person.hbx_id} of Family with id: #{family.id}")
        end
      end
    end

    context 'when data_source is fa_application' do
      let(:start_of_year) { TimeKeeper.date_of_record.beginning_of_year }
      let(:application) { FactoryBot.create(:financial_assistance_application, effective_date: start_of_year) }
      let(:applicant1) { FactoryBot.create(:financial_assistance_applicant, :with_home_address, is_primary_applicant: true, application: application) }
      let(:applicant2) { FactoryBot.create(:financial_assistance_applicant, :with_home_address, is_primary_applicant: false, application: application) }
      let(:relationship) { application.relationships.create!(applicant_id: applicant1.id, relative_id: applicant2.id, kind: 'spouse') }
      let(:input_params) do
        {
          data_source: 'fa_application',
          application_id: relationship.application.id,
          effective_date: start_of_year,
          households: [
            {
              household_id: 'a12bs6dbs1',
              members: [
                {
                  applicant_id: applicant1.id,
                  relationship_with_primary: 'self'
                },
                {
                  applicant_id: applicant2.id,
                  relationship_with_primary: 'spouse'
                }
              ]
            }
          ]
        }
      end
      let(:primary_rating_address) { application.primary_applicant.rating_address }

      let(:county_zip) do
        ::BenefitMarkets::Locations::CountyZip.find_or_create_by!(
          county_name: primary_rating_address.county,
          zip: primary_rating_address.zip,
          state: primary_rating_address.state
        )
      end

      let(:rating_area) do
        ::BenefitMarkets::Locations::RatingArea.find_or_create_by!(
          active_year: start_of_year.year,
          county_zip_ids: [county_zip.id],
          exchange_provided_code: 'ME0'
        )
      end

      let(:service_area) do
        ::BenefitMarkets::Locations::ServiceArea.find_or_create_by!(
          active_year: start_of_year.year,
          county_zip_ids: [county_zip.id],
          issuer_provided_code: "Some issuer code",
          issuer_profile_id: BSON::ObjectId.new
        )
      end

      context 'valid input' do
        before do
          rating_area
          service_area
          @result = subject.call({ application: relationship.application, benchmark_product_model: @benchmark_product_model })
        end

        it 'return success' do
          expect(@result.success).to be_a(::Entities::BenchmarkProducts::BenchmarkProduct)
          expect(@result.success.rating_area_id).to eq(rating_area.id)
          expect(@result.success.exchange_provided_code).to eq(rating_area.exchange_provided_code)
          expect(@result.success.service_area_ids).to eq([service_area.id])
        end
      end
    end
  end
end
