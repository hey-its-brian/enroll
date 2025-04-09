# frozen_string_literal: true

FactoryBot.define do
  factory :income_evidence, class: 'FinancialAssistance::Evidences::IncomeEvidence' do
    key { 'income_evidence' }
    title { 'Income Evidence' }
    description { 'Evidence for income verification' }
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
