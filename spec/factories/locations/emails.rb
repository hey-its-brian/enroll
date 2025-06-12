# frozen_string_literal: true

FactoryBot.define do
  factory :location_email, class: 'Locations::Email' do
    kind { 'home' }
    sequence(:address, 1_111_111) { |n| "#{n}@example.com"}

    trait :for_testing do
      kind { 'home' }
      area_code { "101" }
      number { "1234567" }
      extension { "111" }
      country_code { "1" }
    end

    trait :work do
      kind { 'work' }
    end

    trait :without_kind do
      kind { ' ' }
    end

    trait :without_area_code do
      area_code { ' ' }
    end

    trait :without_number do
      number { ' ' }
    end

    trait :work do
      kind { 'work' }
    end

    trait :mobile do
      kind { 'mobile' }
    end

    factory :invalid_location_email, traits: [:without_kind, :without_email_address]

  end
end
