# frozen_string_literal: true

FactoryBot.define do
  factory :individual_market_applicant, class: 'IndividualMarket::Applicant' do
    association :application, factory: :individual_market_application

    family_member_id { BSON::ObjectId.new }
    person_id { BSON::ObjectId.new }

    trait :with_person_name do
      after(:build) do |applicant|
        applicant.person_name = FactoryBot.build(:person_name)
      end
    end

    trait :with_demographics do
      after(:build) do |applicant|
        applicant.demographics = FactoryBot.build(:individual_market_demographics)
      end
    end

    trait :with_ivl_eligibility do
      after(:build) do |applicant|
        applicant.eligibilities << FactoryBot.build(:individual_market_eligibility)
      end
    end

    trait :with_aptc_csr_eligibility do
      after(:build) do |applicant|
        applicant.eligibilities << FactoryBot.build(:aptc_csr_eligibility)
      end
    end

    trait :with_eligibilities do
      after(:build) do |applicant|
        applicant.eligibilities << FactoryBot.build(:individual_market_eligibility)
        applicant.eligibilities << FactoryBot.build(:aptc_csr_eligibility)
      end
    end
  end
end
