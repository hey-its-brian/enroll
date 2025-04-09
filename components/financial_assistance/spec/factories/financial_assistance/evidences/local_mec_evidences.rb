# frozen_string_literal: true

FactoryBot.define do
  factory :local_mec_evidence, class: 'FinancialAssistance::Evidences::LocalMecEvidence' do
    key { 'local_mec_evidence' }
    title { 'Local Mec Evidence' }
    description { 'Evidence for local government-provided minimum essential coverage' }
    is_satisfied { false }
    current_state { :initial }

    trait :pending do
      current_state { :pending }
    end

    trait :outstanding do
      current_state { :outstanding }
    end

    trait :verified do
      current_state { :verified }
      is_satisfied { true }
    end
  end
end
