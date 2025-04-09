# frozen_string_literal: true

FactoryBot.define do
  factory :v3_eligibility, class: 'Eligibilities::V3::Eligibility' do
    # key { :eligibility }
    # title { 'Eligibility' }
    # description { 'Eligibility determination' }
    current_state { :initial }
    is_satisfied { false }
    is_disqualified { false }

    trait :individual_market_eligibility do
      key { :individual_market_eligibility }
      title { 'Individual Market Eligibility' }
      description { 'Eligibility determination for individual market coverage' }
    end

    trait :magi_medicaid_eligibility do
      key { :magi_medicaid_eligibility }
      title { 'MAGI Medicaid Eligibility' }
      description { 'Eligibility determination for MAGI Medicaid coverage' }
    end

    trait :aptc_csr_eligibility do
      key { :aptc_csr_eligibility }
      title { 'APTC CSR Eligibility' }
      description { 'Eligibility determination for APTC CSR' }
    end

    trait :satisfied do
      is_satisfied { true }
      current_state { :eligible }
      determined_at { Time.current }
    end

    trait :disqualified do
      is_disqualified { true }
      disqualified_at { Time.current }
      disqualified_reason { 'Failed verification' }
    end

    trait :with_determinations do
      transient do
        determinations_count { 1 }
      end

      after(:build) do |eligibility, evaluator|
        # This would require a determination factory to be implemented
        # evaluator.determinations_count.times do
        #   eligibility.determinations << build(:v3_determination)
        # end
      end
    end

    trait :with_evidences do
      transient do
        evidences_count { 1 }
      end

      after(:build) do |eligibility, evaluator|
        # This would require an evidence factory to be implemented
        # evaluator.evidences_count.times do
        #   eligibility.evidences << build(:v3_evidence)
        # end
      end
    end
  end
end
