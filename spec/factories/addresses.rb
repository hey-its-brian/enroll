FactoryBot.define do
  factory :address do
    kind { 'home' }
    sequence(:address_1, 1111) { |n| "#{n} Awesome Street NE" }
    sequence(:address_2, 111) { |n| "##{n}" }
    city { 'Washington' }
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

    trait :valid_county do
      county do
        county_record = ::BenefitMarkets::Locations::CountyZip.where(state: Settings.aca.state_abbreviation).first&.county_name
        return county_record if county_record
        ::BenefitMarkets::Locations::CountyZip.create!(
          county_name: 'Hampden', zip: '01001', state: Settings.aca.state_abbreviation
        )
        ::BenefitMarkets::Locations::CountyZip.where(state: Settings.aca.state_abbreviation).first.county_name
      end
    end

    trait :work_kind do
      kind { 'work' }
    end

    trait :mailing_kind do
      kind { 'mailing' }
    end

    trait :without_kind do
      kind { ' ' }
    end

    trait :without_address_1 do
      address_1 { ' ' }
    end

    trait :without_city do
      city { ' ' }
    end

    trait :without_state do
      state { ' ' }
    end

    trait :without_zip do
      zip { ' ' }
    end

    factory :invalid_address, traits: [:without_kind, :without_address_1,
      :without_city, :without_state, :without_zip]
  end
end
