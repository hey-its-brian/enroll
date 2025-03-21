# frozen_string_literal: true

FactoryBot.define do
  factory :eligibilities_evidence_state, class: '::Eligibilities::EvidenceState' do
    sequence(:evidence_gid) { |n| "gid://app/Evidence/#{n}" }
    sequence(:subject_gid) { |n| "gid://app/Person/#{n}" }
    evidence_item_key { ::Eligibilities::EvidenceState::ALL_VERIFICATION_TYPES.sample }
    status { :verified }
    is_satisfied { true }
    verification_outstanding { false }
    visited_at { DateTime.now - 1.day }
    meta { {} }

    trait :verified do
      status { :verified }
      is_satisfied { true }
      verification_outstanding { false }
      due_on { nil }
    end

    trait :outstanding do
      status { :pending }
      is_satisfied { false }
      verification_outstanding { true }
      due_on { Date.today + rand(10..60).days }
    end

    trait :review do
      status { :review }
      verification_outstanding { true }
      is_satisfied { false }
    end
  end
end