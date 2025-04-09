# frozen_string_literal: true

FactoryBot.define do
  factory :eligibilities_eligibility_state, class: '::Eligibilities::EligibilityState' do
    eligibility_item_key { ['aca_individual_market_eligibility', 'aptc_csr_credit'].sample }
    document_status { 'verified' }
    is_eligible { true }
    determined_at { DateTime.now }

    trait :verified do
      earliest_due_date { nil }
      after(:build) do |state|
        state.evidence_states << build(:eligibilities_evidence_state, :verified)
      end
    end

    trait :with_outstanding_verification do
      earliest_due_date { Date.today + 30.days }
      after(:build) do |state|
        state.evidence_states << build(:eligibilities_evidence_state, :outstanding)
        state.evidence_states << build(:eligibilities_evidence_state, :verified)
      end
    end

    trait :with_review_verification do
      earliest_due_date { Date.today + 30.days }
      after(:build) do |state|
        state.evidence_states << build(:eligibilities_evidence_state, :review)
        state.evidence_states << build(:eligibilities_evidence_state, :verified)
      end
    end
  end
end
