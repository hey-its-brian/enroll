# frozen_string_literal: true

FactoryBot.define do
  factory :aptc_determination, class: 'Eligibilities::V3::Determinations::AptcDetermination' do
    association :eligibility, factory: :aptc_csr_eligibility

    is_eligible { true }
    key { :aptc_determination }

    trait :with_basis do
      after(:build) do |determination|
        determination.bases << build(:v3_basis, determination: determination)
      end
    end
  end
end
