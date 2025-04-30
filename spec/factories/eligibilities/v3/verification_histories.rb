# frozen_string_literal: true

FactoryBot.define do
  factory :v3_verification_history, class: 'Eligibilities::V3::VerificationHistory' do
    action { "Admin Hub Call" }
    update_reason { "System call" }
    updated_by { "Admin" }
    is_satisfied { true }
    verification_outstanding { false }
    due_on { Date.today }
  end
end
