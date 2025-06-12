# frozen_string_literal: true

FactoryBot.define do
  factory :local_mec_evidence, class: 'FinancialAssistance::Evidences::LocalMecEvidence' do
    key { 'local_mec_evidence' }
    title { 'Local Mec Evidence' }
    description { 'Evidence for local government-provided minimum essential coverage' }
    is_satisfied { false }
    current_state { :initial }

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
        create_list(:v3_state_history, 2, status_trackable: evidence)
      end
    end

    # With verification histories
    trait :with_verification_histories do
      after(:create) do |evidence|
        create_list(:v3_verification_history, 2, evidence: evidence)
      end
    end
  end
end
