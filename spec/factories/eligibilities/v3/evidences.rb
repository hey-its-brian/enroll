# frozen_string_literal: true

FactoryBot.define do
  factory :v3_evidence, class: 'Eligibilities::V3::Evidence' do
    sequence(:key) { |n| :"evidence_#{n}" }
    sequence(:title) { |n| "Evidence #{n}" }
    sequence(:description) { |n| "Description for evidence #{n}" }
    is_satisfied { false }
    current_state { :initial }

    trait :verification_succeded do
      current_state { :verification_succeded }
      determined_at { DateTime.current }
      is_satisfied { true }
    end

    trait :verification_failed do
      current_state { :verification_failed }
      determined_at { DateTime.current }
      is_satisfied { false }
    end
  end
end
