# frozen_string_literal: true

FactoryBot.define do
  factory :v3_state_history, class: 'Eligibilities::V3::StateHistory' do
    effective_on { Date.current }
    is_eligible { true }
    from_state { :initial }
    to_state { :eligible }
    transition_at { DateTime.current }
    reason { "Evidence requirements satisfied" }
  end
end
