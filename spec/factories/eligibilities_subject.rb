# frozen_string_literal: true

FactoryBot.define do
  factory :eligibilities_subject, class: '::Eligibilities::Subject' do
    sequence(:gid) { |n| "gid://app/Person/#{n}" }
    sequence(:first_name) { |n| "FirstName#{n}" }
    sequence(:last_name) { |n| "LastName#{n}" }
    sequence(:person_id) { |n| "person-#{n}" }
    sequence(:hbx_id) { |n| "hbx-#{n}" }
    dob { Date.today - 30.years }
    is_primary { false }
    outstanding_verification_status { 'verified' }

    trait :with_outstanding_verification do
      outstanding_verification_status { 'outstanding' }
      after(:build) do |subject|
        subject.eligibility_states << build(:eligibilities_eligibility_state, :with_outstanding_verification)
      end
    end

    trait :as_primary do
      is_primary { true }
    end

    after(:build) do |subject|
      subject.eligibility_states << build(:eligibilities_eligibility_state, :verified) if subject.eligibility_states.empty?
    end

    before(:create, &:add_full_name)
  end
end
