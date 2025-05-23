# frozen_string_literal: true

FactoryBot.define do
  factory :immigration_evidence, class: 'Eligibilities::V3::Evidences::ImmigrationEvidence' do
    association :eligibility, factory: :v3_eligibility

    key { 'immigration_evidence' }
    title { 'Immigration Evidence' }
    description { 'Evidence to verify if a person has a valid Immigration Status' }
    is_satisfied { false }
    current_state { :initial }

    # Fields from EvidenceUtils
    verification_outstanding { false }

    # Different states the evidence can be in
    trait :pending do
      current_state { :pending }
    end

    trait :verified do
      current_state { :verified }
      is_satisfied { true }
    end

    trait :rejected do
      current_state { :rejected }
    end

    trait :outstanding do
      current_state { :outstanding }
      due_on { TimeKeeper.date_of_record + 30.days }
    end

    # With state histories
    trait :with_state_histories do
      after(:create) do |evidence|
        create_list(:state_history, 2, status_trackable: evidence)
      end
    end
  end
end
