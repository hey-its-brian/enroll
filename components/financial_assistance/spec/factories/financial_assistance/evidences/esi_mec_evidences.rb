# frozen_string_literal: true

FactoryBot.define do
  factory :esi_mec_evidence, class: 'FinancialAssistance::Evidences::EsiMecEvidence' do
    key { 'esi_mec_evidence' }
    title { 'Esi Mec Evidence' }
    description { 'Evidence for employer sponsored minimum essential coverage' }
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
