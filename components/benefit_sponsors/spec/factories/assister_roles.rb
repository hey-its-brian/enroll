# frozen_string_literal: true

FactoryBot.define do
  factory :assister_role do
    person { FactoryBot.create(:person, :with_work_phone, :with_work_email) }
    assister_org_id do
      Forgery('basic').text(:allow_lower => false,
                            :allow_upper => false,
                            :allow_numeric => true,
                            :allow_special => false, :exactly => 8)
    end

    provider_kind {"assister"}

    trait :with_invalid_provider_kind do
      provider_kind { ' ' }
    end
  end
end
