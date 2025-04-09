# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_application, class: 'IndividualMarket::Application' do
    family do
      FactoryBot.create(
        :family,
        :with_primary_family_member,
        person: FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      )
    end

    _type { 'IndividualMarket::Application' }
  end
end
