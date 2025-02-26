# frozen_string_literal: true

FactoryBot.define do
  factory :assister_agency_staff_role do
    person
    aasm_state { "active" }
  end
end
