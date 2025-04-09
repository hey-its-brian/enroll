# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_work_email, class: 'ContactProfile::WorkEmail' do
    association :email, factory: :contact_profile_email

    address { 'testing@work.com' }
  end
end
