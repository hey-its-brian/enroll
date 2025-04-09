# frozen_string_literal: true

FactoryBot.define do
  factory :aptc_csr_eligibility, class: 'Eligibilities::V3::AptcCsrEligibility' do
    title { 'APTC CSR Eligibility' }
    key { :aptc_csr_eligibility }
    current_state { :initial }
    is_satisfied { false }

    trait :eligible do
      current_state { :eligible }
      is_satisfied { true }
      determined_at { DateTime.current }
    end

    trait :ineligible do
      current_state { :ineligible }
      is_satisfied { false }
      determined_at { DateTime.current }
    end

    trait :disqualified do
      is_disqualified { true }
      disqualified_at { DateTime.current }
      disqualified_reason { "Failed to provide required documentation" }
    end

    # Add state history
    trait :with_state_history do
      after(:build) do |eligibility|
        eligibility.state_histories << FactoryBot.build(:v3_state_history, status_trackable: eligibility)
      end
    end

    # Add evidence
    trait :with_evidence do
      after(:build) do |eligibility|
        eligibility.evidences << FactoryBot.build(:v3_evidence, eligibility: eligibility)
      end
    end

    # Add determination
    trait :with_determination do
      after(:build) do |eligibility|
        eligibility.determinations << FactoryBot.build(:v3_determination, eligibility: eligibility)
      end
    end
  end
end
