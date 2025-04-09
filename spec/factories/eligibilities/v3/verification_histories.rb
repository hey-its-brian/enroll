# frozen_string_literal: true

FactoryBot.define do
  factory :v3_verification_history, class: 'Eligibilities::V3::VerificationHistory' do
    action { "Admin Hub Call" }
    modifier { "Admin" }
    update_reason { "System call" }
    updated_by { "Admin" }
    is_satisfied { true }
    verification_outstanding { false }
    due_on { Date.today }
    aasm_state { "verified" }
  end
end
