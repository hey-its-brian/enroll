# frozen_string_literal: true

FactoryBot.define do
  factory :sbm_application, class: 'Sbm::Application' do
    family do
      FactoryBot.create(
        :family,
        :with_primary_family_member,
        person: FactoryBot.create(:person, :with_consumer_role, :with_active_consumer_role)
      )
    end
  end
end
