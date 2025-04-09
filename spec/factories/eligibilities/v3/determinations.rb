# frozen_string_literal: true

FactoryBot.define do
  factory :v3_determination, class: 'Eligibilities::V3::Determination' do
    is_eligible { true }
  end
end
