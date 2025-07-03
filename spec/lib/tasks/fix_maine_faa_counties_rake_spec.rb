# frozen_string_literal: true

require 'rails_helper'
require File.join(Rails.root, "app", "helpers", "me_county_helper")

describe 'Fix Maine FAA Counties', :dbclean => :around_each do
  include MeCountyHelper

  let(:family) { FactoryBot.create(:family, :with_primary_family_member) }
  let(:person) { family.primary_applicant.person }
  let(:application) do
    FactoryBot.create(:financial_assistance_application,
                      family_id: family.id,
                      assistance_year: 2024,
                      aasm_state: 'determined')
  end
  let(:applicant) { FactoryBot.create(:applicant, application: application) }
  let(:invalid_address) do
    address = FactoryBot.build(:financial_assistance_address,
                               zip: '04101',
                               city: 'Portland',
                               county: nil,
                               state: 'ME')
    applicant.addresses << address
    applicant.save!(validate: false)
    address
  end

  before do
    load File.expand_path("#{Rails.root}/lib/tasks/fix_maine_faa_counties.rake", __FILE__)
    Rake::Task.define_task(:environment)
    allow_any_instance_of(Object).to receive(:maine_counties_and_towns).and_return({
                                                                                     'Cumberland' => ['Portland', 'South Portland'],
                                                                                     'York' => ['Biddeford', 'Saco']
                                                                                   })
  end

  describe 'migrations:fix_maine_faa_counties' do
    before do
      Rake::Task["migrations:fix_maine_faa_counties"].reenable
      invalid_address
      allow_any_instance_of(Object).to receive(:find_impacted_application_ids).and_return([application.hbx_id])
      allow_any_instance_of(Object).to receive(:address_county_valid?).and_return(false)
    end

    it 'should fix addresses with missing counties' do
      allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
        .with(zip: '04101')
        .and_return([double(county_name: 'Cumberland')])

      allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
        .with(county_name: 'Cumberland', zip: '04101')
        .and_return([double(county_name: 'Cumberland')])

      csv_mock = double('csv')
      allow(csv_mock).to receive(:<<)
      allow(CSV).to receive(:open).and_yield(csv_mock)

      Rake::Task["migrations:fix_maine_faa_counties"].invoke

      expect(applicant.reload.addresses.first.county).to eq('Cumberland')
    end

    it 'should handle addresses with multiple counties by ZIP' do
      county_zip1 = double(county_name: 'Cumberland')
      county_zip2 = double(county_name: 'York')

      allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
        .with(zip: '04101')
        .and_return([county_zip1, county_zip2])
      allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
        .with(county_name: 'Cumberland', zip: '04101')
        .and_return([double(county_name: 'Cumberland')])

      Rake::Task["migrations:fix_maine_faa_counties"].invoke

      expect(applicant.reload.addresses.first.county).to eq('Cumberland')
    end

    it 'should generate a CSV with failures' do
      allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
        .with(zip: '04101')
        .and_return([])

      allow(File).to receive(:write)
      expect(CSV).to receive(:open).with(Rails.root.join('tmp', 'county_fix_failures.csv'), 'w').at_least(:once)

      Rake::Task["migrations:fix_maine_faa_counties"].invoke
    end
  end

  describe 'migrations:generate_impact_list' do
    before do
      Rake::Task["migrations:generate_impact_list"].reenable
      invalid_address
      allow_any_instance_of(Object).to receive(:find_impacted_application_ids).and_return([application.hbx_id])
      allow_any_instance_of(Object).to receive(:address_county_valid?).and_return(false)
    end

    it 'should generate impact list CSV' do
      expect(CSV).to receive(:open).with(Rails.root.join('tmp', 'county_fix_impacts.csv'), 'w').at_least(:once)

      expect { Rake::Task["migrations:generate_impact_list"].invoke }
        .to output(/Report file generated at:/).to_stdout
    end

    it 'should include impacted addresses in the report' do
      csv_data = []
      allow(CSV).to receive(:open) do |_path, _mode, &block|
        csv_mock = double('csv')
        allow(csv_mock).to receive(:<<) { |row| csv_data << row }
        block.call(csv_mock)
      end

      Rake::Task["migrations:generate_impact_list"].invoke

      data_rows = csv_data.reject { |row| row[0] == "Family HBX ID" }
      expect(data_rows).to include([person.hbx_id, application.hbx_id, '="04101"', 'Portland', nil, 'ME'])
    end
  end

  describe 'helper methods' do
    describe '#address_county_valid?' do
      let(:valid_address) do
        address = FactoryBot.build(:financial_assistance_address,
                                   zip: '04101',
                                   city: 'Portland',
                                   county: 'Cumberland',
                                   state: 'ME')
        applicant.addresses << address
        applicant.save!(validate: false)
        address
      end

      it 'returns true for valid addresses' do
        allow(valid_address).to receive(:valid?).and_return(true)
        expect(address_county_valid?(valid_address)).to be_truthy
      end

      it 'returns false for addresses with county/zip validation errors' do
        error_mock = double('error', type: 'invalid county/zip')
        errors_mock = double('errors', errors: [error_mock])

        allow(invalid_address).to receive(:valid?).and_return(false)
        allow(invalid_address).to receive(:errors).and_return(errors_mock)

        expect(address_county_valid?(invalid_address)).to be_falsey
      end
    end

    describe '#counties_by_zip' do
      it 'returns county zip records for given zip' do
        county_zips = [double(county_name: 'Cumberland')]
        allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
          .with(zip: '04101')
          .and_return(county_zips)

        expect(counties_by_zip('04101')).to eq(county_zips)
      end
    end

    describe '#county_by_city' do
      it 'returns county for given city' do
        expect(county_by_city('Portland')).to eq('Cumberland')
      end

      it 'returns nil for unknown city' do
        expect(county_by_city('Unknown City')).to be_nil
      end
    end

    describe '#fix_address' do
      it 'fixes address with single county match' do
        allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
          .with(zip: invalid_address.zip)
          .and_return([double(county_name: 'Cumberland')])

        expect(invalid_address).to receive(:save)
        fix_address(invalid_address)
        expect(invalid_address.county).to eq('Cumberland')
      end

      it 'uses city lookup when multiple counties exist for ZIP' do
        county_zip1 = double(county_name: 'Cumberland')
        county_zip2 = double(county_name: 'York')

        allow(::BenefitMarkets::Locations::CountyZip).to receive(:where)
          .with(zip: invalid_address.zip)
          .and_return([county_zip1, county_zip2])

        expect(invalid_address).to receive(:save)
        fix_address(invalid_address)
        expect(invalid_address.county).to eq('Cumberland')
      end
    end
  end
end
