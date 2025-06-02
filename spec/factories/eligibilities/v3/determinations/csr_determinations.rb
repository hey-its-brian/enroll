# frozen_string_literal: true

FactoryBot.define do
  factory :csr_determination, class: 'Eligibilities::V3::Determinations::CsrDetermination' do
    association :eligibility, factory: :aptc_csr_eligibility

    is_eligible { true }
    csr_type { 'csr_73' }

    trait :with_csr_100 do
      csr_type { 'csr_100' }
    end

    trait :with_csr_94 do
      csr_type { 'csr_94' }
    end

    trait :with_csr_87 do
      csr_type { 'csr_87' }
    end

    trait :with_csr_0 do
      csr_type { 'csr_0' }
    end

    trait :with_csr_limited do
      csr_type { 'csr_limited' }
    end

    trait :without_csr do
      is_eligible { false }
      csr_type { nil }
    end

    trait :with_basis do
      after(:build) do |determination|
        determination.bases << build(:v3_basis, basis_kind: 'ai_na_attested', determination: determination)
      end
    end
  end
end
