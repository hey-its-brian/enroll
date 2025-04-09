# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_email, class: 'ContactProfile::Email' do
    association :contact_detail, factory: :contact_profile_contact_detail

    trait :with_personal_email do
      personal_email { FactoryBot.build(:contact_profile_personal_email, email: self) }
    end

    trait :with_work_email do
      work_email { FactoryBot.build(:contact_profile_work_email, email: self) }
    end
  end
end
