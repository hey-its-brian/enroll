# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_demographics, class: 'IndividualMarket::Demographics' do
    association :applicant, factory: :individual_market_applicant

    gender              { 'Male' }
    dob                 { Date.current - 25.years }
    is_incarcerated     { false }
    indian_tribe_member { false }
    is_physically_disabled { false }
  end
end
