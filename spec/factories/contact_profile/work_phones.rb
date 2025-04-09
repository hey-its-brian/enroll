# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_work_phone, class: 'ContactProfile::WorkPhone' do
    association :phone, factory: :contact_profile_phone

    country_code { '1' }
    area_code { '555' }
    number { '1234567' }
    extension { '' }
    primary { true }
  end
end
