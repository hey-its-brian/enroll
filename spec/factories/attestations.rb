# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_attestation, class: 'IndividualMarket::Attestation' do
    association :application, factory: :individual_market_application

    enrollment_terms { true }
  end
end
