# frozen_string_literal: true

FactoryBot.define do
  factory :v3_basis, class: 'Eligibilities::V3::Basis' do
    association :determination, factory: :v3_determination

    basis_kind { 'state_residency' }
    is_satisfied { true }
  end
end
