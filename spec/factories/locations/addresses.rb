# frozen_string_literal: true

FactoryBot.define do
  factory :location_address, class: 'Locations::Address' do
    kind { 'home' }
    sequence(:address_1, 1111) { |n| "#{n} Test St NE" }
    sequence(:address_2, 111) { |n| "##{n}" }
    city { 'Agawam' }
    state { Settings.aca.state_abbreviation }
    zip { '01001' }
    county { 'Hampden' }

    before(:create) do |address|
      ::BenefitMarkets::Locations::CountyZip.find_or_create_by!(
        county_name: address.county,
        state: address.state,
        zip: address.zip
      )
    end

    trait :work_kind do
      kind { 'work' }
    end

    trait :mailing_kind do
      kind { 'mailing' }
    end
  end
end
