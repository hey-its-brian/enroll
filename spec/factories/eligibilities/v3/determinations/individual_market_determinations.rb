# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_determination, class: 'Eligibilities::V3::Determinations::IndividualMarketDetermination' do
    association :eligibility, factory: :aptc_csr_eligibility

    is_eligible { true }

    trait :with_basis do
      after(:build) do |determination|
        determination.bases << build(:v3_basis, determination: determination)
      end
    end
  end
end
