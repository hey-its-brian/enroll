# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_relationship, class: 'IndividualMarket::Relationship' do
    association :application, factory: :individual_market_application

    kind { IndividualMarket::Relationship::RELATIONSHIP_KINDS.sample }
    source_id { BSON::ObjectId.new }
    relative_id { BSON::ObjectId.new }
  end
end
