# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_contact_detail, class: 'ContactProfile::ContactDetail' do
    contactable { nil }

    trait :with_phone do
      phones { [FactoryBot.build(:contact_profile_phone, contact_detail: self)] }
    end

    trait :with_email do
      emails { [FactoryBot.build(:contact_profile_email, contact_detail: self)] }
    end

    trait :with_preference do
      preferences { [FactoryBot.build(:contact_profile_preference, contact_detail: self)] }
    end
  end
end
