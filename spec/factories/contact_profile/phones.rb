# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_phone, class: 'ContactProfile::Phone' do
    association :contact_detail, factory: :contact_profile_contact_detail

    trait :with_mobile_phone do
      mobile_phone { FactoryBot.build(:contact_profile_mobile_phone, phone: self) }
    end

    trait :with_work_phone do
      work_phone { FactoryBot.build(:contact_profile_work_phone, phone: self) }
    end
  end
end
