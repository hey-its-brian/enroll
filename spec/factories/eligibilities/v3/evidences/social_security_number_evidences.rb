# frozen_string_literal: true

FactoryBot.define do
  factory :social_security_number_evidence, class: 'Eligibilities::V3::Evidences::SocialSecurityNumberEvidence' do
    association :eligibility, factory: :v3_eligibility

    key { 'social_security_number_evidence' }
    title { 'Social Security Number Evidence' }
    description { 'Evidence to verify if the person attested SSN is their own' }
    is_satisfied { false }
    current_state { :initial }

    # Fields from EvidenceUtils
    received_at { Time.now }
    verification_outstanding { false }

    # Different states the evidence can be in
    trait :pending do
      current_state { :pending }
    end

    trait :verified do
      current_state { :verified }
    end

    trait :rejected do
      current_state { :rejected }
    end

    trait :outstanding do
      current_state { :outstanding }
    end

    # With state histories
    trait :with_state_histories do
      after(:create) do |evidence|
        create_list(:state_history, 2, status_trackable: evidence)
      end
    end
  end
end
