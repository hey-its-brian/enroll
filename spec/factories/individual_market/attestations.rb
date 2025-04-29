# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_attestation, class: 'IndividualMarket::Attestation' do
    association :application, factory: :individual_market_application

    signer_role { 'consumer' }
    signer_id { BSON::ObjectId.new }
    signed_at { DateTime.now }
  end
end
