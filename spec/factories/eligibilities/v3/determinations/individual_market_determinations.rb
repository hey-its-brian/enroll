# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_determination, class: 'Eligibilities::V3::Determinations::IndividualMarketDetermination' do
    association :eligibility, factory: :aptc_csr_eligibility

    is_eligible { true }
    key { :individual_market_determination }

    trait :with_basis do
      after(:build) do |determination|
        determination.bases << build(:v3_basis, determination: determination)
      end
    end

    trait :with_all_bases_satisfied do
      after(:build) do |determination|
        determination.bases << build(:v3_basis, basis_kind: 'applying_coverage', is_satisfied: true, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'is_alive', is_satisfied: true, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'state_resident', is_satisfied: true, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'lawfully_present_in_us', is_satisfied: true, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'not_incarcerated', is_satisfied: true, determination: determination)
      end
    end

    trait :with_unsatisfied_bases do
      after(:build) do |determination|
        determination.bases << build(:v3_basis, basis_kind: 'applying_coverage', is_satisfied: true, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'is_alive', is_satisfied: false, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'state_resident', is_satisfied: false, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'lawfully_present_in_us', is_satisfied: true, determination: determination)
        determination.bases << build(:v3_basis, basis_kind: 'not_incarcerated', is_satisfied: true, determination: determination)
      end
    end
  end
end
