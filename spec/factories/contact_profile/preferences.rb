# frozen_string_literal: true

FactoryBot.define do
  factory :contact_profile_preference, class: 'ContactProfile::Preference' do
    association :contact_detail, factory: :contact_profile_contact_detail

    contact_methods       { %w[email mail text] }
    language_preference   { 'English' }
  end
end
