# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_personal_email, class: 'ContactProfile::PersonalEmail' do
    association :email, factory: :contact_profile_email

    address { 'testing@personal.com' }
  end
end
