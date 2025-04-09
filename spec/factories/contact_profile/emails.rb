# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_email, class: 'ContactProfile::Email' do
    association :contact_detail, factory: :contact_profile_contact_detail

    work_email { 'testing@work.com' }
    personal_email { 'testing@personal.com' }
  end
end
